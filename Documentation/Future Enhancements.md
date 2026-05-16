# Future Enhancements

This document captures improvements that would be made for a fully production-hardened deployment. The current platform is intentionally scoped as a functional demo — everything here represents deliberate trade-offs, not oversights.

---

## Networking

**NetworkPolicy enforcement**
Flannel provides overlay networking but does not enforce Kubernetes NetworkPolicies. The policies are already declared in `gitops/operators/postgres/network-policies.yaml` and are ready to enforce — they just need a CNI that supports them. Replacing Flannel with [Calico](https://docs.tigera.io/calico/latest/about/) or [Cilium](https://cilium.io/) would activate enforcement with no changes to the policy manifests.

**TLS termination**
The platform currently serves traffic over HTTP. Adding [cert-manager](https://cert-manager.io/) via Flux and a `ClusterIssuer` backed by Let's Encrypt would enable automatic certificate provisioning and HTTPS termination at the ingress. The ingress manifests already use ingress-nginx — only the TLS annotations and certificate CR would need to be added.

**Cloud IAP instead of open SSH**
SSH is currently open to all IPs (`0.0.0.0/0`) with key-only auth and fail2ban as mitigations. For production on GCP, [Cloud IAP tunneling](https://cloud.google.com/iap/docs/using-tcp-forwarding) would eliminate the need to expose port 22 entirely, replacing it with identity-aware, audited access through the GCP control plane.

---

## Security

**Customer-managed encryption keys (CMEK)**
Terraform state in GCS and all Secret Manager secrets are encrypted with Google-managed keys by default. For stricter compliance requirements, Customer-Managed Encryption Keys (CMEK) via Cloud KMS would give full control over key rotation and revocation, and enable access audit trails at the key level.

**Image scanning and provenance**
Container images (Adminer, CloudNativePG, Prometheus stack) are pulled from public registries. A production setup would mirror images to GCP Artifact Registry, scan them with [Trivy](https://trivy.dev/) or [Grype](https://github.com/anchore/grype) before promotion, and optionally verify provenance attestations with [cosign](https://github.com/sigstore/cosign).

**Pod Security Admission**
The cluster runs without Pod Security Admission profiles configured at the namespace level. Adding `baseline` or `restricted` profiles per namespace would prevent privilege escalation, host path mounts, and other risky pod configurations from being applied — even accidentally.

**Kubernetes audit logging**
k3s audit logging is not enabled. Enabling it and shipping logs to Cloud Logging would provide a full audit trail of API server activity, which is a requirement for most compliance frameworks (SOC 2, ISO 27001).

---

## Observability

**Prometheus AlertRules**
Alertmanager is deployed but alerting rules are not configured. The following CloudNativePG alerts would be the first to add:
- Replication lag > 10 seconds
- WAL archiving failure (barman-cloud not shipping segments)
- Postgres instance down
- Database size growth > 80% of available storage

**Grafana provisioning via CRDs**
The CloudNativePG Grafana dashboard (ID 20417) is currently referenced by ID. In a production setup, the [Grafana Operator](https://grafana.github.io/grafana-operator/) or Grafana's built-in sidecar provisioning would manage dashboard and datasource configuration declaratively via Kubernetes CRs, making dashboard management a GitOps operation.

**ingress-nginx metrics**
A `ServiceMonitor` for ingress-nginx would expose request latency, error rates, and connection counts to Prometheus. Currently only CloudNativePG metrics are scraped.

---

## Reliability

**Automated backup restore testing**
Backups are taken daily and WAL is archived continuously, but the restore procedure is not tested automatically. A weekly CI job that spins up a fresh cluster, performs a point-in-time restore, queries the database, and tears it down would verify backup integrity without manual intervention.

**Pod Disruption Budgets**
No PDBs are defined for CloudNativePG instances or the demo application. Adding PDBs ensures that automated node drains (during k3s upgrades or routine maintenance) cannot simultaneously evict enough pods to break quorum or take the application offline.

**Concurrency protection for deployments**
Two simultaneous merges to `main` could race for the Terraform state lock. Adding a [GitHub Actions concurrency group](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/using-concurrency) to the deploy workflow would serialize deployments and prevent partial-apply races.

**Rollback automation**
If `post-deploy-checks.yml` fails, the current behaviour is to leave the failed state in place and alert the engineer. A production setup would include an automated rollback step that reverts the Terraform state to the last known-good apply and re-runs Ansible.

---

## Multi-tenancy

**Per-customer environment isolation**
The current dev/prod split demonstrates environment separation for a single customer. For multi-tenant deployments, each customer would get their own `gitops/clusters/<customer>/` entry point pointing at the shared `operators/` and `applications/` manifests with customer-specific variable overrides. Terraform would provision separate GCP projects or at minimum separate VPCs per customer to enforce data and billing isolation.

**Separate Terraform state buckets per environment**
Dev and prod currently share the same GCS state bucket under different prefixes. Separate buckets per environment would eliminate any blast radius overlap — a misconfigured destroy in dev could not touch prod state.

---

## Cost and Capacity

**Resource quotas and limit ranges**
Namespaces have no resource quotas. Adding `ResourceQuota` and `LimitRange` objects per namespace would prevent a runaway workload from consuming all cluster resources and would enforce default requests/limits on pods that don't specify them.

**Cost estimation in CI**
Integrating [Infracost](https://www.infracost.io/) into the `validate` workflow would add a cost delta comment to every PR that touches Terraform — catching expensive changes before they are applied.
