# 🔒 Security Considerations

## 🎯 Purpose of This Document

This document describes the security posture of the platform: how secrets are managed, how access is controlled at every layer, and what network policies are in place. It also flags where the current design makes deliberate trade-offs for simplicity and what production hardening would look like.

---

## 🔑 Secret Management

### 🤔 The core principle

**No secret ever enters Git or a CI log.** All credentials flow through a single path:

```text
  Terraform (random_password)
      │  generates at provisioning time
      ▼
  Google Secret Manager
      │  stores as a versioned secret
      ▼
  External Secrets Operator
      │  polls Secret Manager, materialises as a Kubernetes Secret
      ▼
  Workload
      │  references the Secret by name — never sees a plaintext value
      ▼
  CloudNativePG / Grafana / Adminer
```

Passwords are treated as infrastructure: generated once at `terraform apply` time by `random_password`, stored in Secret Manager, and never entered or seen by a human. If a password needs to be rotated, update the value in Secret Manager — ESO will sync it into the cluster within its poll interval and the workload will restart with the new credential.

### 📋 What lives in Secret Manager

| Secret | Who creates it | Who reads it |
|---|---|---|
| `{env}-pg-app-password` | Terraform `random_password` | ESO → CloudNativePG |
| `{env}-pg-superuser-password` | Terraform `random_password` | ESO → CloudNativePG |
| `{env}-grafana-admin-password` | Terraform `random_password` | ESO → Grafana (via `valuesFrom`) |

The `{env}` prefix matches the environment name (`dev` or `prod`). Each environment's Terraform creates its own set of secrets. ESO uses `${ENVIRONMENT}` as a Flux substitution variable to reference the right secret at runtime.

### 🔍 What gitleaks enforces

The `repo-checks.yml` workflow runs [gitleaks](https://github.com/gitleaks/gitleaks) on every PR. It scans the full git history for known secret patterns (API keys, passwords, private keys, tokens) and blocks merge if anything is found. This is the safety net that prevents accidental secret commits.

A `.gitleaks.toml` allowlist at the repo root holds fingerprints of confirmed false positives — specifically a deleted documentation file that contained the literal text `-----BEGIN RSA PRIVATE KEY-----` as a copy-paste instruction, not an actual key. Any new false positive should be added there with a comment explaining why it is safe.

### 🔐 GitHub Actions secrets

CI secrets (GCP project ID, WIF provider, service account, SSH key, state bucket) are stored in GitHub Actions secrets at the repository level and are shared across environments. The SSH private key in particular is set via `gh secret set` in the bootstrap script — it never passes through Terraform state, a file on disk, or a CI log.

The subnet CIDR is **not** stored as a secret. After `terraform apply` runs, CI reads it back from a Terraform output (`terraform output -raw subnet_cidr`) and passes it directly to Ansible. This keeps the value in one place (Terraform) rather than duplicating it in secrets where it would have to be kept in sync manually.

---

## 👤 Access Control

### ☁️ GCP access from CI (Workload Identity Federation)

CI never uses a long-lived service account key. Instead, GitHub Actions authenticates to GCP via **Workload Identity Federation**:

```text
  GitHub Actions job
      │  presents OIDC token (signed by GitHub)
      ▼
  GCP Workload Identity Pool
      │  validates token against GitHub's JWKS endpoint
      │  checks repo and branch conditions
      ▼
  GCP service account impersonation
      │  grants a short-lived access token (1h TTL)
      ▼
  CI job has GCP access with no stored key
```

The bootstrap Terraform module sets this up automatically. The CI service account is granted only the permissions it needs:

| Permission | Why |
|---|---|
| `compute.instances.*` | Provision and query GCE VMs |
| `storage.objects.*` | Read/write Terraform state and backups |
| `secretmanager.versions.access` | Read secrets for ESO |
| `iam.serviceAccounts.actAs` | Required for WIF impersonation |

### 🔒 Cluster access (kubectl)

The Kubernetes API (port 6443) is firewalled to the `admin_cidr` only — not open to the internet. CI does not talk to the API directly; the post-deploy verification pipeline SSHes into the control plane and runs `sudo k3s kubectl` there.

RBAC is managed by k3s defaults. For production, define explicit ClusterRoles and RoleBindings scoped to each team or application.

### 🛡️ Node access (SSH)

SSH (port 22) is currently open to `0.0.0.0/0`. This is a deliberate trade-off: GitHub Actions runners have dynamic IPs so a CIDR restriction is not practical. The real protection layers are:

- **Key-based auth only** — password login is disabled by the `security` Ansible role
- **Root login disabled** — `PermitRootLogin no` in sshd_config
- **fail2ban** — bans IPs after repeated failed attempts (1h ban window)

> 🏭 For production: replace the open SSH rule with **GCP Cloud IAP tunneling** (`gcloud compute ssh --tunnel-through-iap`). IAP proxies SSH through Google's infrastructure — nodes need no public SSH port at all, and access is controlled by Google IAM.

### 🌐 GitHub Environment protection

GitHub Actions Environments (`dev` and `prod`) scope deployment jobs to their respective environments. To add a human approval gate before `terraform apply` runs on production, configure **required reviewers** on the `prod` Environment in repository settings. Without this, any push to the `prod` branch triggers an immediate deploy.

---

## 🌐 Network Policies

### 🔥 GCE VPC Firewall

The firewall is the first layer of network security — it controls what traffic reaches the nodes at all:

| Rule | Source | Ports | Reason |
|---|---|---|---|
| SSH | `0.0.0.0/0` | 22 | GitHub Actions runners have dynamic IPs — see trade-off note above |
| Kubernetes API | `admin_cidr` | 6443 | Operator access only; CI uses SSH |
| HTTP/HTTPS ingress | `0.0.0.0/0` | 80, 443 | Public-facing application traffic |
| Internal cluster | `subnet_cidr` | all | k3s, Flannel CNI, and kubelet need unrestricted intra-node communication |

### 🔄 Intra-cluster traffic (Flannel CNI)

k3s uses **Flannel** as its CNI. Flannel provides overlay networking so pods can communicate across nodes, but it does not enforce any NetworkPolicies by default — all pod-to-pod traffic is allowed.

### ⚙️ Kubernetes NetworkPolicies

A NetworkPolicy is defined for the Postgres namespace (`gitops/operators/postgres/network-policies.yaml`). It denies all ingress to Postgres pods except port 5432 from the `demo-app` namespace.

> ⚠️ Flannel does not enforce NetworkPolicies natively — the policy is declared but not enforced in the current setup. To enforce it, install a NetworkPolicy-capable CNI alongside Flannel (e.g. Calico in policy-only mode) or switch to a CNI that supports them natively (e.g. Cilium). In k3s, this requires replacing Flannel entirely.

For production, the recommended baseline on top of the existing policy:

- Default-deny all ingress and egress within each namespace
- Explicit allow: Postgres replicas ↔ primary (streaming replication, port 5432)
- Explicit allow: ESO → Secret Manager (egress to Google APIs)
- Explicit allow: Prometheus → PodMonitor targets (scrape port 9187)
- Explicit allow: ingress-nginx → application pods
- Explicit allow: DNS resolution (egress to kube-dns, port 53)
