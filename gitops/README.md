# 🔄 GitOps

This directory is the **single source of truth** for everything that runs inside the Kubernetes cluster. Flux, running inside the cluster, watches this repository and continuously reconciles the cluster state toward what is declared here. If something drifts — a pod is manually deleted, a config is changed with `kubectl` — Flux corrects it within 60 seconds.

No one runs `kubectl apply` to deploy things. You open a PR, get it reviewed, merge it, and Flux handles the rest. 🙌

## 📁 Structure

```
gitops/
  clusters/
    dev/                          ← Flux entry point for the dev cluster
      common.yaml                 ← Flux Kustomization → clusters/common
      postgres.yaml               ← Flux Kustomization → operators/postgres
      demo-app.yaml               ← Flux Kustomization → applications/demo-app
    prod/                         ← same structure, same shared manifests, different cluster-vars
      common.yaml
      postgres.yaml
      demo-app.yaml
    common/                       ← shared cluster platform components (ingress, monitoring, ESO)
  operators/
    postgres/                     ← CloudNativePG operator + HA cluster + secrets
  applications/
    demo-app/                     ← Adminer deployment + service + ingress
```

## 🔁 How Flux reconciles the cluster

When Flux bootstraps (done by Ansible during the first CI run), it creates a `GitRepository` resource pointing at this repo and a root `Kustomization` pointing at `gitops/clusters/<env>`. From that point it works like this:

```
Flux watches gitops/clusters/dev/
    │
    ├── common.yaml    →  reconciles gitops/clusters/common/
    │       installs: ingress-nginx, External Secrets Operator, kube-prometheus-stack
    │       (must be healthy before the next layer starts ✅)
    │
    ├── postgres.yaml  →  reconciles gitops/operators/postgres/
    │       installs: CloudNativePG operator
    │       creates:  3-instance HA PostgreSQL cluster, ExternalSecrets for credentials
    │       (depends on common — ESO must be ready to pull secrets 🔐)
    │
    └── demo-app.yaml  →  reconciles gitops/applications/demo-app/
            deploys:  Adminer (database UI), service, ingress
            (depends on postgres — cluster must be ready before app starts 🐘)
```

The `dependsOn` field in each Flux Kustomization enforces this order. Flux will not attempt to reconcile a layer until all its dependencies are healthy.

## 🌍 Shared manifests, per-environment config

The manifests in `clusters/common/`, `operators/`, and `applications/` are **shared** — both `clusters/dev` and `clusters/prod` point at exactly the same files. No duplication. Environment-specific values are injected at reconcile time via Flux post-build variable substitution.

Two ConfigMaps in the `flux-system` namespace supply these variables (created by the Ansible `flux` role during bootstrap):

| ConfigMap | Keys | Scope |
|---|---|---|
| `cluster-global` | `GCP_PROJECT_ID` | Same for all environments (single GCP project) |
| `cluster-vars` | `ENVIRONMENT`, `REGION` | Per-environment; REGION can differ if dev and prod run in different GCP regions |

Every Flux Kustomization references both via `postBuild.substituteFrom`. Manifests use `${VARIABLE}` syntax wherever an environment-specific value is needed (e.g. `gs://${ENVIRONMENT}-${GCP_PROJECT_ID}-pg-backups`).

➕ Adding a new environment (e.g. staging) means:
1. Create `gitops/clusters/staging/` with the three Kustomization files
2. Point them at the same shared manifest directories
3. The Ansible bootstrap for that cluster creates the right `cluster-vars` for staging

No manifest duplication, no divergence.

## 🛠️ Common layer (`clusters/common/`)

Cluster-wide tooling managed as HelmReleases:

| Component | What it does |
|---|---|
| 🌐 **ingress-nginx** | L7 ingress controller; routes HTTP/HTTPS traffic into the cluster |
| 🔐 **External Secrets Operator** | Pulls secrets from GCP Secret Manager and materialises them as Kubernetes Secrets |
| 📊 **kube-prometheus-stack** | Prometheus + Grafana + alerting; pre-configured with CloudNativePG dashboard |

All Helm chart sources are declared as `HelmRepository` resources in `sources.yaml`.

## 🐘 Postgres layer (`operators/postgres/`)

Three resources work together:

- 📦 **`cloudnativepg.yaml`** — installs the CloudNativePG operator via HelmRelease
- 🔐 **`external-secrets.yaml`** — three `ExternalSecret` resources that pull the superuser, app user, and replication passwords from GCP Secret Manager and create Kubernetes Secrets
- 🗄️ **`cluster.yaml`** — the `Cluster` CR that tells the operator to create a 3-instance HA PostgreSQL 16 cluster with GCS backups, `PodMonitor` for metrics, and topology spread constraints so each instance lands on a different node

Credentials never touch Git. They live in Secret Manager (written there by Terraform's `random_password` resource) and are pulled into the cluster by ESO.

## 🖥️ Demo app (`applications/demo-app/`)

**Adminer** — a lightweight, single-container database UI. It demonstrates a working end-to-end connection: Adminer → Postgres service → CloudNativePG primary pod. Deployed as a `Deployment` + `Service` + `Ingress`, all reconciled by Flux.

## ✏️ Making a change

**Application or cluster config change** (anything in `gitops/`):
```
edit file → push branch → open PR → merge → Flux picks it up within 60 seconds ⚡
```

No CI job runs for GitOps changes. Flux polls the repository every 60 seconds and applies any diff it finds.

**Infrastructure change** (anything in `terraform/` or `ansible/`):
```
edit file → push branch → open PR (CI runs terraform plan) → merge → CI applies
```

For the full picture of how this fits into the CI pipeline, see the [Technical Analysis](../docs/technical-analysis.md).
