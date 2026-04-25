# 🏛️ Architecture Overview

## 🗺️ Platform Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            GIT REPOSITORY (GitHub)                              │
│                                                                                 │
│   terraform/           ansible/           gitops/            docs/              │
│   ├── modules/         ├── roles/         ├── clusters/       ├── architecture  │
│   │   ├── network      │   ├── base       │   ├── dev/        └── runbooks/     │
│   │   ├── node         │   ├── k8s        │   └── prod/                         │
│   │   └── firewall     │   └── security   ├── operators/                        │
│   └── environments/    └── playbooks/     │   └── postgres/                     │
│       ├── dev/             bootstrap.yml  └── applications/                     │
│       └── prod/                               └── demo-app/                     │
└───────────────┬──────────────────────┬──────────────────────────────────────────┘
                │                      │
        terraform apply        ansible-playbook bootstrap.yml
                │                      │
                │              ┌───────┴────────────────────┐
                │              │ roles/base                 │
                │              │ roles/kubernetes  (k3s)    │
                │              │ roles/security             │
                │              │ roles/flux   (bootstrap)   │
                │              └───────┬────────────────────┘
                ▼                      ▼
┌──────────────────────────────────────────────────────────┐
│                      GOOGLE CLOUD (GCE)                  │
│                                                          │
│   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   │
│   │   node-01   │   │   node-02   │   │   node-03   │   │
│   │  (control)  │   │  (worker)   │   │  (worker)   │   │
│   │             │   │             │   │             │   │
│   │  k3s server │   │  k3s agent  │   │  k3s agent  │   │
│   │  flux-system│   │             │   │             │   │
│   └──────┬──────┘   └──────┬──────┘   └──────┬──────┘   │
│          └─────────────────┴─────────────────┘          │
│                        Flannel CNI                       │
│                   NetworkPolicies enforced               │
│                                                          │
│   VPC Firewall: 22 (SSH)  6443 (API)  80/443 (ingress)   │
└───────────────────────────┬──────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                             KUBERNETES CLUSTER                                  │
│                                                                                 │
│   ┌───────────────────────────────────────────────────────────────────────┐     │
│   │   namespace: flux-system                                              │     │
│   │                                                                       │     │
│   │   Flux  ──── git pull (reconcile loop, 60s) ◄──── GitHub repo         │     │
│   │   ├── GitRepository CR                                                │     │
│   │   └── Kustomization CR                                                │     │
│   │     │                                                                 │     │
│   └─────┼─────────────────────────────────────────────────────────────────┘     │
│         │ deploys / reconciles                                                  │
│         ├─────────────────────────────────────────────────────┐                 │
│         │                                                     │                 │
│         ▼                                                     ▼                 │
│   ┌──────────────────────────────────┐   ┌───────────────────────────────┐      │
│   │   namespace: postgres            │   │   namespace: demo-app         │      │
│   │                                  │   │                               │      │
│   │   CloudNativePG Operator         │   │   Adminer (Deployment)        │      │
│   │                                  │   │   ├── 1 replica               │      │
│   │   Cluster CR                     │   │   ├── envFrom: secret         │      │
│   │   ├── pg-1  (primary)  ──────────────────► connects to Postgres      │      │
│   │   ├── pg-2  (replica)            │   │   └── Ingress / Service       │      │
│   │   └── pg-3  (replica)            │   └───────────────────────────────┘      │
│   │          │                       │                                          │
│   │   ScheduledBackup CR             │   ┌───────────────────────────────┐      │
│   │   └──► GCS bucket (barman)       │   │   namespace: monitoring       │      │
│   │                                  │   │                               │      │
│   │   PodMonitor CR                  │   │   Prometheus                  │      │
│   │   └──► Prometheus scrape         │   │   Grafana                     │      │
│   │                                  │   │   Alertmanager                │      │
│   │   Secrets via External Secrets   │   └───────────────────────────────┘      │
│   │   └──► Google Secret Manager     │                                          │
│   └──────────────────────────────────┘                                          │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘

   GCS Bucket  ◄── CloudNativePG barman-cloud-backup (WAL + base backups)
```

> 📝 **Demo application note:** The example application is **Adminer** — a lightweight database UI that connects to Postgres and can read and write data interactively. The task suggests a containerized REST API as one possible example; Adminer was chosen instead because it requires zero application code, directly exercises database authentication and network connectivity, and makes the end-to-end verification immediately visual. In a real platform, this slot would be replaced by a customer workload.

---

## 🔁 CI Pipeline Design

Three GitHub Actions workflows cover the full repository:

| Workflow | Trigger | Path filter | Purpose |
|----------|---------|-------------|---------|
| `repo-checks.yml` | Every PR | None — catches everything | Secret scanning, YAML lint, Markdown lint |
| `validate.yml` | Every PR | `terraform/**`, `ansible/**`, `gitops/**` | Terraform plan, Ansible lint, manifest validation |
| `deploy.yml` | Merge to main | `terraform/**`, `ansible/**` | Terraform apply, Ansible bootstrap |

**Why two separate validate/deploy files instead of one?**
The split keeps the read-only safety check (validate) clearly separated from the destructive operation (apply). It also means validate can run on untrusted PRs without needing the same secret access that apply requires.

**Why not one pipeline per component (terraform, ansible, gitops)?**
The terraform → ansible dependency makes this impractical: Ansible needs node IPs from Terraform output, which would require complex cross-workflow artifact passing or querying GCP directly. For a team larger than ~5 engineers or a multi-customer setup, per-component pipelines with a dedicated orchestration layer (e.g. Atlantis for Terraform) would be the right call.

**Approval gate:**
The PR review process is the implicit approval gate before `terraform apply` runs. For stricter control, configure required reviewers on the `dev` GitHub Environment in repo settings — this adds an explicit human approval step before deploy.yml proceeds.

---

## 🔄 GitOps Change Flow

Every change to the cluster goes through Git — no one runs `kubectl apply` by hand. Here's what happens from the moment you push code to the moment the cluster reflects it:

```
  Engineer              GitHub             flux-system            Cluster
     │                     │                    │                    │
     ├── git push ─────────►                    │                    │
     │                     ├── PR / review       │                    │
     │◄── merge approved ──┤                    │                    │
     │                     │◄── poll (60s) ─────┤                    │
     │                     ├── diff detected ───►                    │
     │                     │                    ├── reconcile ───────►
     │                     │                    │◄── ready ──────────
     │                     │                    │                    │
```

---

## ⬆️ PostgreSQL Minor Upgrade Flow

Upgrading Postgres is a Git operation. The operator handles the rolling restart with zero downtime — replicas restart first, then the primary fails over to a healthy replica before restarting itself:

```
  1. Engineer bumps imageName in Cluster CR and opens PR
  2. PR reviewed and merged to main
  3. Flux detects diff, reconciles Cluster CR to cluster
  4. CloudNativePG operator detects image change
  5. Rolling restart begins:
        replica pg-3  →  restart  →  healthy
        replica pg-2  →  restart  →  healthy
        primary pg-1  →  failover to pg-2  →  restart  →  rejoin as replica
  6. Zero downtime — replicas serve reads throughout
```

---

## 🌐 Ingress and Load Balancing

External traffic reaches the cluster through **ingress-nginx**, which is exposed via a Service of type `LoadBalancer`. On this platform, k3s's built-in **ServiceLB** (klipper-lb) handles that Service — it binds ports 80 and 443 directly on every node, so any node's external IP can receive traffic.

```
External client → node external IP (port 80/443) → k3s ServiceLB → ingress-nginx → application
```

> 💰 A proper production setup would sit a **GCE L4 load balancer** in front of the nodes, giving you a single stable public IP and automatic failover if a node goes down. We deliberately skip this here to keep infrastructure costs to a minimum — this is a demo platform, not a customer-facing service.

---

## 🗄️ Storage Design

Postgres storage is intentionally different between environments. The `STORAGE_CLASS` variable is injected into each cluster's `cluster-vars` ConfigMap by Ansible at bootstrap time, and Flux substitutes it into the `Cluster` CR:

| Environment | Storage Class | Backing | Durability |
|-------------|---------------|---------|------------|
| dev | `local-path` | Local node disk (k3s default) | Lost if the node VM is deleted — CNPG resyncs from primary |
| prod | `standard` | GCE Persistent Disk (CSI driver) | Network-attached, survives node deletion |

> ⚠️ For prod to work, the GCE PD CSI driver must be installed on the cluster before Flux reconciles the Postgres `Cluster` CR. Without it, the `standard` StorageClass does not exist and the PVCs will not be provisioned.

The tradeoff is deliberate: dev uses local disk for simplicity and speed; prod uses network-attached storage for the durability guarantees a production database requires.

---

## 💾 Backup and Restore

Two mechanisms run in parallel to protect your data. WAL archiving gives you continuous coverage; base backups give you a faster restore starting point:

```
  BACKUP
  ──────
  ScheduledBackup CR  (e.g. daily 02:00 UTC)
  ├── WAL streaming  ─────────────────────────► GCS bucket
  └── base backup (barman-cloud-backup) ───────► GCS bucket

  RESTORE
  ───────
  1. Create new Cluster CR with:
         bootstrap:
           recovery:
             source: cluster-backup
             recoveryTarget:
               targetTime: "2026-03-15T03:00:00Z"
  2. CloudNativePG pulls base backup from GCS
  3. CloudNativePG replays WAL up to target time
  4. Cluster comes online at point-in-time
```
