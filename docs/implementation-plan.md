# Implementation Plan

## Overview

Six phases in strict dependency order. Each phase must be complete and tested before the next begins. CI validation gates enforce this on every PR.

```
Phase 1: Repository skeleton
    ↓
Phase 2: Terraform (GCP infrastructure)
    ↓
Phase 3: Ansible (node config + k3s + Flux bootstrap)
    ↓
Phase 4: GitOps manifests (Flux tree, operators, app)
    ↓
Phase 5: CI workflows (GitHub Actions)
    ↓
Phase 6: Documentation (README, timetable, leadership answers)
```

---

## Phase 1 — Repository Skeleton

Create the full directory structure upfront so all subsequent phases have a home.

**Tasks:**

- [ ] Create directory tree:
  ```
  terraform/
    modules/
      network/
      node/
      firewall/
      gcs/
      iam/
    environments/
      dev/
      prod/
  ansible/
    roles/
      base/
      kubernetes/
      security/
      flux/
    playbooks/
    inventory/
  gitops/
    clusters/
      dev/
      prod/
    infrastructure/
      controllers/        ← operator installs (CNPG, ESO, Prometheus)
    operators/
      postgres/
    applications/
      demo-app/
  .github/
    workflows/
  docs/
  ```
- [ ] Add `.gitkeep` files to empty leaf directories
- [ ] Add root `.gitignore` (Terraform state, `.terraform/`, Ansible vault files, kubeconfig)

**Estimated time: 30 min**

---

## Phase 2 — Terraform

Provision all GCP infrastructure. Nothing is installed on the nodes at this stage.

### 2.1 Provider and backend config

- [ ] `terraform/environments/dev/versions.tf` — pin `google` provider version, configure GCS backend for remote state
- [ ] `terraform/environments/dev/variables.tf` — project ID, region, zone, environment name, node count, machine type
- [ ] `terraform/environments/prod/` — mirror of dev with different variable defaults (can be a stub for now)

### 2.2 Module: network

- [ ] `google_compute_network` — custom VPC (not default)
- [ ] `google_compute_subnetwork` — subnet with defined CIDR
- [ ] Outputs: network name, subnetwork name, subnetwork self-link

### 2.3 Module: node

- [ ] `google_compute_address` (INTERNAL) — reserved static internal IP per node (mandatory for k3s stability)
- [ ] `google_compute_instance` — GCE VM, attached to subnet, uses reserved IP
  - machine type: `e2-standard-2`
  - OS: Ubuntu 22.04 LTS
  - metadata: SSH public key injection
  - service account attached (from iam module)
- [ ] Outputs: instance names, internal IPs, external IPs

### 2.4 Module: firewall

- [ ] `google_compute_firewall` — allow rules:
  - SSH (22) from operator CIDR only
  - Kubernetes API (6443) from operator CIDR only
  - HTTP/HTTPS (80/443) from anywhere
  - Internal cluster traffic (all protocols within subnet CIDR)
- [ ] Default deny all other ingress

### 2.5 Module: gcs

- [ ] `google_storage_bucket` — backup bucket
  - `force_destroy = true` (required for clean `terraform destroy`)
  - versioning enabled
  - lifecycle rule: delete objects older than retention window
- [ ] `google_storage_bucket_iam_member` — grant the node service account `objectAdmin` on the bucket
- [ ] Outputs: bucket name

### 2.6 Module: iam

- [ ] `google_service_account` — dedicated SA for GCE nodes
- [ ] `google_project_iam_member` — bind minimal roles:
  - `roles/secretmanager.secretAccessor` (for ESO)
  - `roles/storage.objectAdmin` scoped to backup bucket
- [ ] Workload Identity binding — allow k8s ServiceAccount in `postgres` namespace to impersonate this SA
- [ ] Outputs: service account email

### 2.7 Secret Manager

- [ ] `google_secret_manager_secret` + `google_secret_manager_secret_version` — seed initial Postgres credentials (username, password, replication password)

### 2.8 Wiring

- [ ] `terraform/environments/dev/main.tf` — instantiate all modules with correct dependencies
- [ ] `terraform/environments/dev/outputs.tf` — expose node IPs and SSH key path (consumed by Ansible inventory)

**Estimated time: 4–6h**

---

## Phase 3 — Ansible

Takes nodes from blank OS to running k3s cluster with Flux bootstrapped. Runs as a single playbook.

### 3.1 Inventory

- [ ] `ansible/inventory/hosts.yml` — dynamic inventory template populated from Terraform outputs
  ```yaml
  all:
    children:
      control:
        hosts:
          node-01:
      workers:
        hosts:
          node-02:
          node-03:
  ```

### 3.2 Role: base

Applies to all nodes.

- [ ] Install system packages (curl, git, apt-transport-https, etc.)
- [ ] Set kernel parameters: `br_netfilter`, `ip_forward`, `overlay` module
- [ ] Install and configure containerd
- [ ] Disable swap (required by Kubernetes)
- [ ] Set hostname per node

### 3.3 Role: kubernetes

- [ ] On `control` group: install k3s server
  - disable default Traefik (we manage ingress via GitOps)
  - write kubeconfig to local machine
  - capture k3s node token
- [ ] On `workers` group: install k3s agent, join cluster using token from control node
- [ ] Wait for all nodes `Ready` before proceeding

### 3.4 Role: security

- [ ] Configure UFW: allow only SSH, 6443, 80, 443 + intra-cluster
- [ ] Disable unnecessary services
- [ ] Set kubelet read-only port to 0
- [ ] Configure auditd (basic rules)

### 3.5 Role: flux

- [ ] Install `flux` CLI on control node
- [ ] Run `flux check --pre` to verify prerequisites
- [ ] Apply Flux install manifests to cluster
- [ ] Create `GitRepository` CR pointing at this repo
- [ ] Create root `Kustomization` CR pointing at `gitops/clusters/dev`
- [ ] Wait for `flux-system` pods `Ready`

### 3.6 Playbook

- [ ] `ansible/playbooks/bootstrap.yml` — orchestrate roles in order:
  `base` → `kubernetes` → `security` → `flux`
  with `serial: 1` for the kubernetes role on workers (join one at a time)

**Estimated time: 4–6h**

---

## Phase 4 — GitOps Manifests

Everything Flux reconciles after bootstrap. Order within the tree is enforced by Flux `dependsOn` between `Kustomization` CRs.

### 4.1 Flux system config

- [ ] `gitops/clusters/dev/flux-system/` — Flux's own config (generated by bootstrap, committed)
- [ ] `gitops/clusters/dev/infrastructure.yaml` — `Kustomization` CR pointing at `gitops/infrastructure/`, depends on nothing
- [ ] `gitops/clusters/dev/operators.yaml` — `Kustomization` CR pointing at `gitops/operators/`, `dependsOn: infrastructure`
- [ ] `gitops/clusters/dev/applications.yaml` — `Kustomization` CR pointing at `gitops/applications/`, `dependsOn: operators`

### 4.2 Infrastructure controllers

- [ ] **cert-manager** — `HelmRelease` (needed by some operators for webhook certs)
- [ ] **CloudNativePG operator** — `HelmRelease` from CNPG helm repo
- [ ] **External Secrets Operator** — `HelmRelease`, configured with `ClusterSecretStore` pointing at Google Secret Manager using Workload Identity
- [ ] **Prometheus stack** — `HelmRelease` (kube-prometheus-stack), with Grafana enabled

### 4.3 Postgres operator config

- [ ] `gitops/operators/postgres/namespace.yaml` — `postgres` namespace
- [ ] `gitops/operators/postgres/cluster.yaml` — CloudNativePG `Cluster` CR:
  - 3 instances (1 primary, 2 replicas)
  - pd-balanced persistent volumes, 20Gi each
  - backup configured to GCS bucket
  - references credentials secret (synced by ESO)
- [ ] `gitops/operators/postgres/backup.yaml` — `ScheduledBackup` CR (daily)
- [ ] `gitops/operators/postgres/monitoring.yaml` — `PodMonitor` CR for Prometheus scraping
- [ ] `gitops/operators/postgres/externalsecret.yaml` — `ExternalSecret` CR pulling Postgres credentials from Secret Manager

### 4.4 Demo application (Adminer)

- [ ] `gitops/applications/demo-app/namespace.yaml`
- [ ] `gitops/applications/demo-app/deployment.yaml` — Adminer deployment, env vars from secret
- [ ] `gitops/applications/demo-app/service.yaml`
- [ ] `gitops/applications/demo-app/ingress.yaml` (optional, or use port-forward for testing)
- [ ] `gitops/applications/demo-app/externalsecret.yaml` — pulls Postgres connection details

**Estimated time: 5–8h**

---

## Phase 5 — CI Workflows

### 5.1 PR validation

- [ ] `.github/workflows/pr-validate.yml`:
  - `terraform fmt -check` on `terraform/**`
  - `terraform validate` on `terraform/**`
  - `terraform plan` on `terraform/**` (requires GCP credentials via Workload Identity Federation)
  - `ansible-lint` on `ansible/**`
  - `kubeconform` on `gitops/**`

### 5.2 Deploy workflow

- [ ] `.github/workflows/deploy.yml`:
  - Triggered on push to `main` when `terraform/**` or `ansible/**` changes
  - Job 1: `terraform apply`
  - Job 2: `ansible-playbook bootstrap.yml` (depends on Job 1, reads node IPs from TF outputs)
  - Flux takes over after Job 2 completes

**Estimated time: 2–3h**

---

## Phase 6 — Documentation

- [ ] `README.md` — top-level: what this is, prerequisites, quickstart (terraform apply → ansible-playbook), how to access Adminer and Grafana, how to destroy
- [ ] `docs/timetable.md` — time per sub-task (fill in actuals as work progresses)
- [ ] `docs/leadership.md` — written answers to the four leadership questions

**Estimated time: 2–3h**

---

## Total Estimate

| Phase | Task | Est. time |
|---|---|---|
| 1 | Repository skeleton | 0.5h |
| 2 | Terraform | 4–6h |
| 3 | Ansible | 4–6h |
| 4 | GitOps manifests | 5–8h |
| 5 | CI workflows | 2–3h |
| 6 | Documentation | 2–3h |
| | **Total** | **17–26h** |

---

## Implementation Order Within a Session

When sitting down to implement, work in this order within each phase — never jump ahead to the next phase until the current one is testable:

1. Scaffold the files (even empty) — structure first
2. Implement and test Terraform in isolation (`terraform plan` locally)
3. Implement and test Ansible roles individually before running the full playbook
4. Build GitOps manifests starting from infrastructure → operators → applications
5. Wire CI last, once the manual flow works end-to-end
