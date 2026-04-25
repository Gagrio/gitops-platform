# ✅ Requirements Checklist

---

## 📦 Delivery

| Item | Status |
|---|---|
| Code in GitHub repository | ✅ |
| README.md | ✅ |
| Timetable with time per sub-task | ✅ In README |
| Leadership answers | ✅ `Documentation/Leadership.md` |
| LLM use documented | ✅ In README |

---

## 1️⃣ Infrastructure Provisioning (Terraform)

| Requirement | Status | Where |
|---|---|---|
| Public/bare metal/local cloud | ✅ GCP | `terraform/environments/dev` |
| 3 Kubernetes nodes | ✅ | `terraform/modules/node` |
| Networking | ✅ VPC + subnet | `terraform/modules/network` |
| SSH access | ✅ Firewall rule + key injection | `terraform/modules/firewall`, `modules/node` |
| Firewall configuration | ✅ | `terraform/modules/firewall` |
| Modular design | ✅ | `terraform/modules/` |
| Environment separation (dev/prod) | ✅ | `terraform/environments/dev`, `environments/prod` |
| Reusable modules | ✅ | `terraform/modules/` |

---

## 2️⃣ Node Configuration (Ansible)

| Requirement | Status | Where |
|---|---|---|
| Install container runtime | ✅ containerd (bundled in k3s) | `ansible/roles/kubernetes` |
| Install Kubernetes | ✅ k3s | `ansible/roles/kubernetes` |
| Configure networking | ✅ Flannel CNI, sysctl, br_netfilter | `ansible/roles/base`, `roles/kubernetes` |
| Prepare cluster for GitOps | ✅ Flux bootstrapped | `ansible/roles/flux` |
| `roles/base`, `roles/kubernetes`, `roles/security` | ✅ | `ansible/roles/` |
| `playbooks/bootstrap.yml` | ✅ | `ansible/playbooks/bootstrap.yml` |
| Idempotent | ✅ | All roles safe to re-run |
| Modular | ✅ | Four independent roles |
| Reusable | ✅ | Parameterised via `--extra-vars` |

---

## 3️⃣ GitOps Deployment

| Requirement | Status | Where |
|---|---|---|
| GitOps tool (ArgoCD preferred / Flux accepted) | ✅ Flux — choice justified in docs | `gitops/`, `ansible/roles/flux` |
| Install operators via GitOps | ✅ CloudNativePG, ESO | `gitops/clusters/common/` |
| Manage application manifests via GitOps | ✅ Adminer | `gitops/applications/demo-app/` |
| Environment separation | ✅ | `gitops/clusters/dev/`, `gitops/clusters/prod/` |

---

## 4️⃣ Operator-Based Stateful Service (CloudNativePG)

| Requirement | Status | Where |
|---|---|---|
| Kubernetes operator (not Helm) | ✅ CloudNativePG | `gitops/operators/postgres/cloudnativepg.yaml` |
| 3 PostgreSQL instances | ✅ | `gitops/operators/postgres/cluster.yaml` |
| Persistent volumes | ✅ | `gitops/operators/postgres/cluster.yaml` |
| Failover configuration | ✅ Automatic via CNPG | `gitops/operators/postgres/cluster.yaml` |
| Backups to object storage | ✅ GCS via barman | `gitops/operators/postgres/cluster.yaml` |
| Scheduled backups | ✅ Daily 02:00 UTC | `gitops/operators/postgres/scheduled-backup.yaml` |
| Restore procedure | ✅ Documented | `Documentation/Operational lifecycle.md` |
| Prometheus metrics | ✅ PodMonitor CR | `gitops/operators/postgres/cluster.yaml` |
| Grafana dashboard | ✅ ID 20417, auto-provisioned | `gitops/clusters/common/kube-prometheus-stack.yaml` |
| PostgreSQL minor upgrade path | ✅ Rolling restart documented | `Documentation/Operational lifecycle.md` |
| GitOps change management for upgrades | ✅ | `Documentation/Operational lifecycle.md` |

---

## 5️⃣ Example Application

| Requirement | Status | Notes |
|---|---|---|
| Application connecting to Postgres | ✅ Adminer | `gitops/applications/demo-app/adminer.yaml` |
| Managed via GitOps | ✅ | Flux reconciles `gitops/applications/demo-app/` |
| REST API (suggested, not required) | ⚠️ Used Adminer instead | Justified in `Documentation/Architecture.md` — zero app code required, directly exercises the full stack |

---

## 📚 Documentation

| Requirement | Status | Where |
|---|---|---|
| Architecture — infrastructure layout | ✅ | `Documentation/Architecture.md` |
| Architecture — cluster architecture | ✅ | `Documentation/Architecture.md` |
| Architecture — GitOps workflow | ✅ | `Documentation/Architecture.md` |
| Operational lifecycle — backup | ✅ | `Documentation/Operational lifecycle.md` |
| Operational lifecycle — restore | ✅ | `Documentation/Operational lifecycle.md` |
| Operational lifecycle — upgrades | ✅ | `Documentation/Operational lifecycle.md` |
| Operational lifecycle — monitoring | ✅ | `Documentation/Operational lifecycle.md` |
| Operational lifecycle — scaling | ✅ | `Documentation/Operational lifecycle.md` |
| Security — secret management | ✅ | `Documentation/Security considerations.md` |
| Security — access control | ✅ | `Documentation/Security considerations.md` |
| Security — network policies | ✅ | `Documentation/Security considerations.md` |

---

## 👥 Leadership

| Requirement | Status | Where |
|---|---|---|
| Team organisation (roles, review, release) | ✅ | `Documentation/Leadership.md` |
| Multi-environment deployments | ✅ | `Documentation/Leadership.md` |
| Reliability (repeatable, testing, safe changes) | ✅ | `Documentation/Leadership.md` |
| Security (network, data, runtime, secrets, access, supply chain) | ✅ | `Documentation/Leadership.md` |

---

## ⚠️ Known Gaps / Deliberate Choices

| Item | Notes |
|---|---|
| ArgoCD vs Flux | Task prefers ArgoCD; Flux was chosen — rationale in `Documentation/Technical analysis.md` |
| REST API vs Adminer | Task suggests a REST API; Adminer was chosen — rationale in `Documentation/Architecture.md` |
| `gitops/infrastructure/` path | Task example uses this name; we use `gitops/clusters/common/` which better reflects that this is shared cluster-level config, not infrastructure |
