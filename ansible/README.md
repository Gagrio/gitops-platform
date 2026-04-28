# ⚙️ Ansible

This directory takes the bare VMs that Terraform provisioned and turns them into a fully bootstrapped, GitOps-ready Kubernetes cluster. Ansible connects over SSH, runs four roles in sequence, and by the time the playbook finishes, Flux is live and already reconciling the cluster. No further manual steps are needed.

## What it does

1. 🖥️ **Prepares the OS** — installs packages, sets kernel parameters, disables swap, loads required kernel modules
2. 🔒 **Hardens the nodes** — SSH configuration, fail2ban, UFW firewall at the OS level
3. ☸️ **Installs Kubernetes** — deploys k3s on the control plane, joins the workers, waits for the cluster to be ready
4. 🔄 **Bootstraps Flux** — installs the Flux CLI, runs `flux bootstrap`, creates the `cluster-vars` ConfigMaps that Flux uses for per-environment variable substitution

## Structure

```text
ansible/
  ansible.cfg                     ← SSH settings, inventory path, role path
  requirements.yml                ← Ansible Galaxy collections (ansible.posix, community.general)
  playbooks/
    bootstrap.yml                 ← the single playbook; runs all four roles in order
  roles/
    base/                         ← OS prep: packages, sysctl, swap, br_netfilter
    security/                     ← SSH hardening, fail2ban, UFW rules
    kubernetes/                   ← k3s install on control plane and workers
    flux/                         ← Flux CLI, bootstrap, cluster ConfigMaps
  inventory/
    group_vars/
      all.yml                     ← shared variables (k3s version, Flux version, etc.)
    hosts.ini.example             ← example inventory; CI generates the real one from Terraform output
```

## The bootstrap playbook

There is one playbook: `playbooks/bootstrap.yml`. It runs all four roles against the right host groups:

```text
All nodes     → base + security
Control plane → kubernetes (control role)
Workers       → kubernetes (worker role)
Control plane → flux
```

The playbook is **idempotent** — it is safe to re-run. If k3s is already installed, the installer script exits immediately. If Flux is already bootstrapped, the bootstrap step is skipped. This means the same playbook handles both first-time installs and re-runs after a config change.

## Roles

### 🖥️ base

Applies to every node. Installs system packages, disables swap (k3s requirement), sets kernel parameters for Kubernetes networking (`net.ipv4.ip_forward`, `net.bridge.bridge-nf-call-iptables`), loads `br_netfilter`, and sets the timezone to UTC.

### 🔒 security

Hardens the SSH daemon (no root login, no password auth, no X11 forwarding), configures fail2ban with a 1-hour ban window, and sets up UFW with an explicit allowlist of ports k3s needs (22, 6443, 80, 443, 10250, 8472/udp). Everything else is denied by default.

### ☸️ kubernetes

On the **control plane**: downloads and runs the k3s installer in server mode, waits for the node token to appear, and shares that token with all hosts so workers can use it. Traefik and the default load balancer are disabled — ingress-nginx and MetalLB are managed via Flux instead.

On **workers**: runs the k3s installer in agent mode using the token and control plane URL shared by the previous step.

### 🔄 flux

Downloads the Flux CLI binary, waits for the cluster API to be reachable, and runs `flux bootstrap github` if Flux isn't already installed. After bootstrapping, it creates two ConfigMaps in the `flux-system` namespace that Flux uses for post-build variable substitution in all Kustomizations:

- `cluster-global` — `GCP_PROJECT_ID` (same across all environments in this project)
- `cluster-vars` — `ENVIRONMENT`, `REGION`, and `STORAGE_CLASS` (per-environment; currently `local-path` for all environments — the k3s built-in provisioner; switching to a GCE PD-backed StorageClass requires installing the GCE CSI driver separately)

Finally, it copies the kubeconfig to `/tmp/kubeconfig-enclaive-dev` so the CI job can upload it as an artifact.

## Inventory

Inventory is **dynamic** — no static `hosts.ini` is generated or uploaded between CI jobs. The `inventory/gcp_compute.yaml` config tells Ansible to query GCP directly for nodes matching `labels.environment=dev`, then group them by their `role` label:

| GCE label | Ansible group |
|---|---|
| `labels.role=control` | `control` |
| `labels.role=worker` | `worker` |
| all matched nodes | `k3s_cluster` |

These labels are set by the Terraform node module at provisioning time — no coordination needed between CI jobs. Authentication uses Application Default Credentials: `gcloud auth application-default login` locally, or the WIF token automatically in CI.

For prod, create `inventory/gcp_compute_prod.yaml` with `filters: [labels.environment=prod]`.

## How CI uses Ansible

CI runs the bootstrap playbook as the second job in the deploy pipeline, after `terraform apply` completes. It authenticates to GCP via WIF (so the dynamic inventory can query GCP), installs Ansible and Galaxy collections, writes the SSH private key, waits for SSH on all nodes, then runs the playbook:

```bash
ansible-playbook playbooks/bootstrap.yml \
  --extra-vars "gcp_project_id=... region=... environment=dev subnet_cidr=... storage_class=local-path github_token=..."
```

The `GCP_PROJECT` environment variable is set in the CI job so the `gcp_compute` inventory plugin knows which project to query. No inventory artifact is generated or passed between jobs.

For the full CI pipeline picture, see the [Technical Analysis](../Documentation/Technical%20analysis.md).
