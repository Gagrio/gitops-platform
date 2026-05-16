# 🏛️ Architecture Overview

## 🗺️ Platform Diagram

```text
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            GIT REPOSITORY (GitHub)                              │
│                                                                                 │
│   terraform/           ansible/           gitops/            Documentation/     │
│   ├── modules/         ├── roles/         ├── clusters/       ├── Architecture  │
│   │   ├── network      │   ├── base       │   ├── dev/        ├── Operations    │
│   │   ├── node         │   ├── kubernetes │   └── prod/       └── Security      │
│   │   └── firewall     │   └── security   ├── operators/                        │
│   └── environments/    └── playbooks/     │   ├── eso-config/                   │
│       ├── dev/             bootstrap.yml  │   ├── monitoring/                   │
│       └── prod/                           │   └── postgres/                     │
│                                           └── applications/                     │
│                                               └── demo-app/                     │
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
│   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐    │
│   │   node-01   │   │   node-02   │   │   node-03   │    │
│   │  (control)  │   │  (worker)   │   │  (worker)   │    │
│   │             │   │             │   │             │    │
│   │  k3s server │   │  k3s agent  │   │  k3s agent  │    │
│   │  flux-system│   │             │   │             │    │
│   └──────┬──────┘   └──────┬──────┘   └──────┬──────┘    │
│          └─────────────────┴─────────────────┘           │
│                        Flannel CNI                       │
│                   NetworkPolicies declared*              │
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
│   │   Cluster CR                     │   │   ├── env: DEFAULT_SERVER     │      │
│   │   ├── pg-1  (primary)  ──────────────────► connects to Postgres      │      │
│   │   ├── pg-2  (replica)            │   │   └── Ingress / Service       │      │
│   │   └── pg-3  (replica)            │   └───────────────────────────────┘      │
│   │          │                       │                                          │
│   │   ScheduledBackup CR             │   ┌───────────────────────────────┐      │
│   │   └──► GCS bucket (barman)       │   │   namespace: monitoring       │      │
│   │                                  │   │                               │      │
│   │   PodMonitor CR                  │   │   Prometheus                  │      │
│   │   └──► Prometheus scrape         │   │   Grafana                     │      │
│   │                                  │   │   (Alertmanager disabled)     │      │
│   │   Secrets via External Secrets   │   └───────────────────────────────┘      │
│   │   └──► Google Secret Manager     │                                          │
│   └──────────────────────────────────┘                                          │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘

   GCS Bucket  ◄── CloudNativePG barman-cloud-backup (WAL + base backups)
```

> *NetworkPolicies are declared in `gitops/operators/postgres/network-policies.yaml` but Flannel does not enforce them natively. The policy is in place for when a NetworkPolicy-capable CNI is added. See Security considerations.md for details.

> 📝 **Demo application note:** The example application is **Adminer** — a lightweight database UI that connects to Postgres and can read and write data interactively. The task suggests a containerized REST API as one possible example; Adminer was chosen instead because it requires zero application code, directly exercises database authentication and network connectivity, and makes the end-to-end verification immediately visual. In a real platform, this slot would be replaced by a customer workload.

---

## 🔁 CI Pipeline Design

Four GitHub Actions workflows cover the full repository:

| Workflow | Trigger | Path filter | Purpose |
|----------|---------|-------------|---------|
| `repo-checks.yml` | Every PR | None — catches everything | Secret scanning, YAML lint, Markdown lint |
| `validate.yml` | Every PR | `terraform/**`, `ansible/**`, `gitops/**` | Terraform plan, Ansible lint, manifest validation |
| `deploy.yml` | Push to `main` or `prod` | `terraform/**`, `ansible/**`, `gitops/**` | Terraform apply, Ansible bootstrap, kubeconfig upload |
| `post-deploy-checks.yml` | After `deploy.yml` succeeds; manual via UI; `scripts/ci/**` changes | — | Wait for Flux convergence + Postgres bootstrap; functional health checks |

**Why two separate validate/deploy files instead of one?**
The split keeps the read-only safety check (validate) clearly separated from the destructive operation (apply). It also means validate can run on untrusted PRs without needing the same secret access that apply requires.

**Why not one pipeline per component (terraform, ansible, gitops)?**
The terraform → ansible dependency makes this impractical: Ansible needs node IPs from Terraform output, which would require complex cross-workflow artifact passing or querying GCP directly. For a team larger than ~5 engineers or a multi-customer setup, per-component pipelines with a dedicated orchestration layer (e.g. Atlantis for Terraform) would be the right call.

**Branch-based environment targeting:**
The target environment is derived from the branch name — no manual selection needed. `main` maps to `dev`; the `prod` branch maps to `prod`. Each cluster's Flux instance watches its own branch, so gitops changes also follow the same promotion path. The `prod` branch has no enforced promotion from `main` — dev and prod can diverge intentionally, which is realistic for infrastructure that often has legitimate long-term differences between environments.

**Inventory — no artifact passing between jobs:**
Ansible inventory is dynamic. The `gcp_compute` plugin (from the `google.cloud` Galaxy collection) queries GCP at Ansible runtime for nodes matching the chosen environment label, then groups them by their `role` label (`control` / `worker`). These labels are set by the Terraform node module at provisioning time, so no inventory file is generated, uploaded, or downloaded between CI jobs — each job authenticates to GCP independently via Workload Identity Federation.

**Approval gate:**
Configure required reviewers on the `prod` GitHub Environment in repo settings — this adds an explicit human approval step before `deploy.yml` proceeds on production.

---

## 🔄 GitOps Change Flow

Every change to the cluster goes through Git — no one runs `kubectl apply` by hand. Here's what happens from the moment you push code to the moment the cluster reflects it:

```text
  Engineer              GitHub             flux-system            Cluster
     │                     │                    │                    │
     ├── git push ─────────►                    │                    │
     │                     ├── PR / review      │                    │
     │◄── merge approved ──┤                    │                    │
     │                     │◄── poll (60s) ─────┤                    │
     │                     ├── diff detected ───►                    │
     │                     │                    ├── reconcile ───────►
     │                     │                    │◄── ready ───────────
     │                     │                    │                    │
```

---

## ⬆️ PostgreSQL Minor Upgrade Flow

Upgrading Postgres is a Git operation — bump `imageName` in the `Cluster` CR and merge. CloudNativePG performs a rolling restart: replicas first, then the primary fails over before restarting. Zero downtime throughout.

See **Operational lifecycle.md → Upgrades** for the full step-by-step flow and the major-version upgrade caveat.

---

## 🔥 Firewall Design

| Rule | Source | Ports | Reason |
|---|---|---|---|
| SSH | `0.0.0.0/0` | 22 | GitHub Actions runners have dynamic IPs — cannot restrict by CIDR. Key-based auth + fail2ban is the protection layer. |
| Kubernetes API | `admin_cidr` | 6443 | Operator personal access only. CI does not need direct API access — it uses SSH to run kubectl on the control plane. |
| HTTP/HTTPS ingress | `0.0.0.0/0` | 80, 443 | Public-facing services. |
| Internal cluster | `subnet_cidr` | all | k3s, Flannel CNI, and kubelet require unrestricted intra-node communication. |

> 🏭 For production, replace the open SSH rule with **GCP Cloud IAP tunneling** (`gcloud compute ssh --tunnel-through-iap`). IAP proxies SSH through Google's infrastructure so nodes never need a public SSH port at all.

---

## 🌐 Ingress and Load Balancing

External traffic reaches the cluster through **ingress-nginx**. ServiceLB (klipper-lb) is disabled in this k3s configuration — ingress-nginx instead uses **hostPort** mode, binding ports 80 and 443 directly to the network interface of whichever node(s) its pods are scheduled on. Use `kubectl get pod -n ingress-nginx -o wide` to find which node(s) are currently hosting the pods before attempting to access services in the browser.

```text
External client → node external IP (port 80/443) → ingress-nginx pod (hostPort) → application
```

> 💰 A proper production setup would sit a **GCE L4 load balancer** in front of the nodes, giving you a single stable public IP and automatic failover if a node goes down. We deliberately skip this here to keep infrastructure costs to a minimum — this is a demo platform, not a customer-facing service.

---

## 🗄️ Storage Design

Both environments use `local-path`, the StorageClass that k3s ships with. It provisions storage directly from the node's local filesystem. The `STORAGE_CLASS` variable is injected into each cluster's `cluster-vars` ConfigMap by Ansible at bootstrap time, and Flux substitutes it into the `Cluster` CR.

| Environment | Storage Class | Backing |
|-------------|---------------|---------|
| dev | `local-path` | Local node disk (k3s default) |
| prod | `local-path` | Local node disk (k3s default) |

This is not a concern for data durability in practice because CNPG handles durability at the database layer:

- **Streaming replication** to two replicas means the dataset exists on three nodes simultaneously — losing one node does not lose data
- **Continuous WAL archiving to GCS** enables point-in-time recovery even if all three nodes were lost

The storage layer does not need to be durable because the database layer already is.

> 🏭 **For a GKE deployment or if you install the GCE PD CSI driver on k3s**, you can switch `STORAGE_CLASS` to `standard` (GCE Persistent Disk) or any other CSI-backed class. This gives network-attached storage that survives node deletion independently of CNPG. The variable is the only thing that needs to change — the Cluster CR and all manifests are already parameterised.

---

## 💾 Backup and Restore

Two mechanisms run in parallel: continuous WAL archiving to GCS (every transaction) and a daily base backup via `barman-cloud-backup` at 02:00 UTC. Together they enable point-in-time recovery to any moment since the last `terraform apply`.

See **Operational lifecycle.md → Database Backup / Database Restore** for retention settings, the full restore Cluster CR, and step-by-step recovery procedure.
