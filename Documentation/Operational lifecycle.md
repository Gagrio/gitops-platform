# 🔧 Operational Lifecycle

## 🎯 Purpose of This Document

This document explains how the platform supports ongoing database and cluster operations. It covers the mechanics of backup, restore, upgrades, monitoring, and scaling — both what happens automatically and what an operator needs to do manually when required.

---

## 💾 Database Backup

Two mechanisms run in parallel to protect your data. Together they provide continuous coverage with a fast restore starting point.

### 📡 WAL Archiving

PostgreSQL continuously ships **Write-Ahead Log** (WAL) segments to the GCS backup bucket via `barman-cloud-wal-archive`. WAL is the low-level transaction journal — every committed change is recorded here before it is applied to the database. This is the foundation of point-in-time recovery: as long as WAL is being archived, you can recover to any moment in time, not just the last backup.

WAL archiving is configured in the `Cluster` CR and runs continuously in the background with no operator intervention.

### 📦 Scheduled Base Backups

The `ScheduledBackup` CR triggers a full base backup via `barman-cloud-backup` every day at **02:00 UTC**. A base backup is a snapshot of the full data directory at a point in time. Combined with WAL, this gives you a faster restore starting point — instead of replaying WAL from the beginning of time, you start from the most recent base backup and replay only the WAL segments after it.

```yaml
# gitops/operators/postgres/scheduled-backup.yaml
schedule: "0 0 2 * * *"   # daily at 02:00 UTC (6-field: seconds minutes hours ...)
```

### 🗂️ Retention

| Environment | WAL retention | Base backup retention |
|---|---|---|
| dev | 30 days | 30 days |
| prod | 30 days | 30 days |

Both are configured in the `Cluster` CR under `backup.barmanObjectStore.retentionPolicy`.

---

## ⏪ Database Restore

Point-in-time recovery is a GitOps operation. You declare the desired recovery target in a new `Cluster` CR — CloudNativePG does the rest.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-restored
  namespace: postgres
spec:
  instances: 3
  bootstrap:
    recovery:
      source: cluster-backup
      recoveryTarget:
        targetTime: "2026-03-15T03:00:00Z"   # recover to this point in time
  externalClusters:
    - name: cluster-backup
      barmanObjectStore:
        destinationPath: gs://${ENVIRONMENT}-${GCP_PROJECT_ID}-pg-backups
        googleCredentials:
          gkeEnvironment: true   # uses GCE node service account — no key file needed
```

What happens after you apply this:

```text
  1. CloudNativePG pulls the most recent base backup from GCS that predates the target time
  2. WAL segments are replayed from the base backup up to the target time
  3. The restored cluster comes online at the exact point-in-time requested
  4. The original cluster (pg) continues running — no data is overwritten
```

> ⚠️ Always restore to a **new** cluster name first. Verify the restored data before promoting it or decommissioning the original cluster.

---

## ⬆️ Upgrades

All upgrades are Git operations. The operator or CI handles the actual execution.

### 🐘 PostgreSQL Minor Upgrade

Bump the `imageName` in the `Cluster` CR and merge. CloudNativePG performs a **rolling restart** — replicas restart first, then the primary fails over to a healthy replica before restarting itself. Zero downtime throughout.

```text
  1. Engineer bumps imageName in gitops/operators/postgres/cluster.yaml and opens PR
  2. PR reviewed and merged to main
  3. Flux detects diff, reconciles Cluster CR
  4. CloudNativePG operator detects image change, begins rolling restart:
        replica pg-3  →  restart  →  healthy
        replica pg-2  →  restart  →  healthy
        primary pg-1  →  failover to pg-2  →  restart  →  rejoin as replica
  5. Zero downtime — replicas serve reads throughout
```

> ⚠️ Major version upgrades (e.g. Postgres 16 → 17) require a different procedure: provision a new cluster, migrate data, then decommission the old one. CloudNativePG does not perform in-place major version upgrades.

### ☸️ k3s Upgrade

Bump `k3s_version` in `ansible/inventory/group_vars/all.yml` and merge. CI runs the bootstrap playbook, which re-runs the k3s installer on all nodes. Ansible checks the running k3s version first and only runs the installer if the version doesn't match — so the upgrade is triggered automatically.

> ⚠️ **Limitation:** The bootstrap playbook upgrades all nodes without draining workloads first. Pods running on a node being upgraded may be interrupted. This is acceptable for dev but not for production workloads that require zero downtime.

The GitOps-native solution for zero-downtime k3s upgrades is the **k3s System Upgrade Controller**:

```text
  1. Deploy the System Upgrade Controller to the cluster (via Flux)
  2. Create a Plan CR in Git pointing at the target k3s version:

         apiVersion: upgrade.cattle.io/v1
         kind: Plan
         metadata:
           name: k3s-server
           namespace: system-upgrade
         spec:
           concurrency: 1          # one node at a time
           version: v1.32.0+k3s1
           nodeSelector:
             matchLabels:
               node-role.kubernetes.io/control-plane: "true"
           drain:
             force: true
           upgrade:
             image: rancher/k3s-upgrade

  3. Flux reconciles the Plan CR
  4. The controller drains each node, upgrades k3s, verifies it rejoins,
     then moves to the next — workers first, control plane last
  5. Zero downtime throughout
```

This approach keeps the upgrade fully declarative and GitOps-driven without modifying the bootstrap playbook.

> 🧹 **After the upgrade completes:** remove the Plan CR from Git and merge. Flux will delete it from the cluster. If you leave it in place, the controller is harmless — it will see the nodes are already at the target version and do nothing. However, leaving it means you now have two sources of truth for the k3s version (`all.yml` and the Plan CR) which will diverge on the next upgrade if you only update one of them.

### 🔄 Flux Upgrade

Bump `flux_version` in `ansible/roles/flux/defaults/main.yml` and merge. The Ansible `flux` role re-runs `flux bootstrap github`, which upgrades the Flux controllers in place.

---

## 📊 Monitoring

### 🔍 What Is Instrumented

CloudNativePG exposes PostgreSQL metrics natively. A `PodMonitor` CR tells Prometheus to scrape those metrics automatically. The `kube-prometheus-stack` Helm release (deployed via Flux) includes Prometheus, Grafana, and the required CRDs.

Key metrics exposed by CloudNativePG:

| Metric | What it tells you |
|---|---|
| `cnpg_pg_replication_lag` | Replication lag between primary and replicas |
| `cnpg_backends_total` | Active database connections |
| `cnpg_pg_database_size_bytes` | Database size on disk |
| `cnpg_collector_wal_buffers_full` | WAL pressure indicator |
| `cnpg_pg_stat_activity_count` | Queries by state (active, idle, waiting) |

### 📈 Grafana

The Grafana instance is pre-provisioned with the **official CloudNativePG dashboard** (Grafana ID 20417). No manual dashboard import needed — Flux reconciles it on first deploy.

Access Grafana via ingress-nginx at the same node IP as Adminer (use `kubectl get pod -n ingress-nginx -o wide` to find which node has the pod):

```text
http://<ingress-node-external-ip>/grafana
```

Retrieve the admin password from Secret Manager:

```bash
gcloud secrets versions access latest --secret=dev-grafana-admin-password
```

Navigate to **Dashboards → CloudNativePG** for the PostgreSQL cluster health dashboard.

### 🚨 Alerting

Alertmanager is deployed but **disabled by default** in this platform — there is no on-call target configured in the demo environment. In production, configure Alertmanager with your notification channel (PagerDuty, Slack, email) and enable the CloudNativePG alerting rules that ship with the dashboard.

---

## 📈 Scaling

### 🖥️ Adding Worker Nodes

Increment `worker_count` in `terraform/environments/dev/main.tf` (or prod), open a PR, and merge. CI runs `terraform apply` to provision the new VM, then runs the Ansible bootstrap playbook which installs k3s agent on the new node and joins it to the cluster. The node appears as `Ready` automatically — no manual steps.

### 🐘 Scaling PostgreSQL Replicas

Change the `instances` field in the `Cluster` CR and merge. CloudNativePG adds or removes replicas automatically, cloning from the primary using streaming replication. Each instance must land on a different node — the `topologySpreadConstraints` in the Cluster CR enforce this.

> ⚠️ Scaling down requires enough nodes to satisfy the spread constraints. If you have 3 nodes and 3 instances and try to scale to 4 instances, the 4th pod will remain `Pending` until a 4th node is available.

### 🖥️ Scaling the Demo Application

Change the `replicas` field in `gitops/applications/demo-app/adminer.yaml` and merge. Flux reconciles the change within 60 seconds.
