# Cloud Native GitOps Platform

A **production-grade GitOps infrastructure platform** that provisions a Kubernetes cluster on Google Cloud, bootstraps it with Ansible, and manages all workloads through Flux. The end state is a platform where no one manually applies Kubernetes manifests — everything is declared in Git and reconciled automatically.

---

## What It Builds

| Layer | Technology | What it does |
|---|---|---|
| Infrastructure | Terraform + GCP | 3 GCE VMs, VPC, firewall, GCS bucket, IAM, Secret Manager |
| Node bootstrap | Ansible + k3s | OS hardening, k3s install, Flux bootstrap |
| GitOps engine | Flux v2 | Continuously reconciles all cluster state from this repo |
| Database | CloudNativePG | 3-instance Postgres HA cluster with WAL archiving + scheduled backups |
| Demo app | Adminer | Database UI — exercises the full Postgres connection end-to-end |
| Observability | Prometheus + Grafana | CloudNativePG metrics, Grafana dashboard provisioned automatically |
| Secrets | External Secrets Operator | Pulls credentials from GCP Secret Manager — nothing sensitive in Git |
| CI | GitHub Actions (4 workflows) | Validate on PR, apply on merge, post-deploy health checks |

---

## How It Works

Three tiers of automation. After the one-time bootstrap you never touch Terraform or Ansible again:

| Tier | Who | When |
|---|---|---|
| **One-time bootstrap** | You, manually | Once, to wire up CI |
| **Infrastructure changes** | GitHub Actions | Push to `main` → deploys dev; push to `prod` → deploys prod |
| **Application/config changes** | Flux | Every 60 seconds, continuously |

The normal workflow is: **open a PR → merge → CI and Flux handle everything**.

---

## Repository Structure

```text
.
├── terraform/
│   ├── bootstrap/              # One-time: CI service account, WIF, GitHub secrets
│   ├── modules/
│   │   ├── network/            # VPC and subnet
│   │   ├── node/               # GCE VM with static internal IP and labels
│   │   ├── firewall/           # Ingress rules (SSH, API, HTTP/S, intra-cluster)
│   │   ├── gcs/                # GCS backup bucket
│   │   └── iam/                # Service accounts, Secret Manager, WIF bindings
│   └── environments/
│       ├── dev/                # dev entry point (e2-standard-2, local-path storage)
│       └── prod/               # prod entry point (e2-standard-4, local-path storage)
│
├── ansible/
│   ├── playbooks/bootstrap.yml # Single idempotent playbook — runs all four roles
│   ├── inventory/
│   │   └── gcp_compute.yaml    # Dynamic inventory — queries GCP by label at runtime
│   └── roles/
│       ├── base/               # OS packages, sysctl, swap, br_netfilter
│       ├── security/           # SSH hardening, fail2ban, UFW
│       ├── kubernetes/         # k3s control plane + worker join
│       └── flux/               # Flux CLI, bootstrap, cluster-vars ConfigMaps
│
├── gitops/
│   ├── clusters/
│   │   ├── common/             # Shared platform: ingress-nginx, ESO, Prometheus stack
│   │   ├── dev/                # Dev entry point — Flux root for the dev cluster
│   │   └── prod/               # Prod entry point — same manifests, different vars
│   ├── operators/
│   │   ├── eso-config/         # ClusterSecretStore and ExternalSecret CRs
│   │   ├── monitoring/         # kube-prometheus-stack HelmRelease
│   │   └── postgres/           # CloudNativePG Cluster CR, ScheduledBackup, NetworkPolicy
│   └── applications/demo-app/  # Adminer Deployment, Service, Ingress
│
├── .github/workflows/
│   ├── repo-checks.yml         # All PRs: secret scan, YAML lint, Markdown lint
│   ├── validate.yml            # terraform plan, ansible-lint, kubeconform
│   ├── deploy.yml              # terraform apply → Ansible bootstrap → kubeconfig upload
│   └── post-deploy-checks.yml  # Flux convergence wait + functional health checks
│
├── scripts/
│   ├── bootstrap.sh            # Automates the one-time setup — run once, CI takes over
│   └── ci/                     # Helper scripts used by GitHub Actions
│       ├── get-node-ips.sh          # Returns node external IPs filtered by GCP labels
│       ├── wait-for-ssh.sh          # Polls until SSH is available on a new node
│       ├── wait-for-convergence.sh  # Waits for Flux kustomizations and Postgres to settle
│       ├── health-check.sh          # Nodes, pods, and Adminer HTTP 200 assertions
│       ├── fetch-kubeconfig.sh      # Copies kubeconfig from control plane for CI artifact upload
│       └── generate-inventory.sh    # Legacy static inventory helper (superseded by gcp_compute plugin)
│
└── Documentation/
    ├── Architecture.md                # Platform diagram, CI design, GitOps flow, storage, backups
    ├── Operational lifecycle.md       # Backup, restore, upgrades, monitoring, scaling
    ├── Security considerations.md     # Secret management, access control, network policies
    ├── Deployment guide.md            # Step-by-step: bootstrap → deploy → verify → day-2
    ├── Technical analysis.md          # Deep dive: every component and every design decision
    └── Future Enhancements.md         # Improvements for a production-grade deployment
```

---

## Quick Start

> **Prerequisites:** `gcloud`, `terraform`, `gh`, and `kubectl` must be installed. See the [Prerequisites section](Documentation/Deployment%20guide.md#-prerequisites) of the Deployment Guide.

Two manual steps, then everything is automated:

```bash
# 1. Authenticate
gcloud auth login
gcloud auth application-default login
gh auth login

# 2. Clone and bootstrap
git clone https://github.com/Gagrio/gitops-platform
cd gitops-platform
bash scripts/bootstrap.sh
```

The script handles everything else: GCS state bucket, SSH key pair, `terraform apply` on the bootstrap module, and all GitHub Actions secrets. After it completes, push any change touching `terraform/` or `ansible/` to `main` and CI deploys to dev automatically.

Full instructions: [Deployment Guide](Documentation/Deployment%20guide.md)

---

## Documentation

| Document | What it covers |
|---|---|
| [Architecture](Documentation/Architecture.md) | Platform diagram, CI pipeline design, GitOps flow, firewall design, storage |
| [Operational Lifecycle](Documentation/Operational%20lifecycle.md) | Backup, restore, upgrades, monitoring, scaling |
| [Security Considerations](Documentation/Security%20considerations.md) | Secret management, access control, network policies |
| [Deployment Guide](Documentation/Deployment%20guide.md) | Bootstrap, deploy, verify, day-2 operations, teardown, troubleshooting |
| [Technical Analysis](Documentation/Technical%20analysis.md) | Design rationale for every component and every decision made |
| [Future Enhancements](Documentation/Future%20Enhancements.md) | What would change for a fully production-hardened deployment |

---

## LLM Use

**Claude (claude-sonnet-4-6 via Claude Code)** was used throughout this project as a pair programmer — for code generation, review, debugging, and documentation writing.

Specifically:

- All Terraform, Ansible, and Kubernetes manifests were written with Claude generating first drafts, reviewed and corrected iteratively
- Claude caught several real bugs during a file-by-file review: `ansible_default_ipv4.address` returning the external GCE IP on multi-homed VMs, `br_netfilter` being loaded after the sysctl settings that depend on it, `hosts: workers` vs `hosts: worker` mismatch
- CI workflows and the bootstrap script were designed and written collaboratively
- All documentation was written with Claude; the content reflects genuine design decisions made during the build

Claude was used exactly as it would be in daily work: as a fast, capable collaborator that still requires human judgement to direct and verify.
