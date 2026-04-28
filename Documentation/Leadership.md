# 👥 Leadership Answers

---

## 1️⃣ Team Organisation

With three people you can't have strict roles — everyone does a bit of everything. But someone still needs to be the go-to person for each area, otherwise nothing gets properly owned. I'd split it roughly like this: one person looks after the infrastructure (Terraform, Ansible, CI pipelines), one focuses on what runs inside the cluster (Flux, operators, monitoring), and one keeps production healthy — backups, alerts, runbooks, what to do when things break. They help each other out, but you know who to call when something goes wrong.

Everything goes through a PR. No pushing directly to main, even for small things. If you're touching Terraform, the infra person has to review it. We also post the terraform plan output in the PR automatically — that way nobody is surprised by what's about to change. Same goes for runbooks; they live in Git and go through review like everything else.

No manual deployments. You merge to main and dev gets updated. You merge to prod and production gets updated. For anything risky — major upgrades, deletions — you need a second person to explicitly approve before it runs.

---

## 2️⃣ Multi-Environment Deployments

The actual YAML files live in shared directories with placeholders like `${STORAGE_CLASS}` or `${REGION}` instead of hardcoded values. Each customer gets a small folder in Git that points Flux at those shared directories and supplies the real values. Flux swaps them in at reconcile time. So if you have ten customers for example and you have one copy of the Postgres definition, not ten, then you fix or upgrade it in one place and everyone gets it on their next rollout. The alternative is copying manifests per customer and watching them slowly drift apart as different people make different changes to each copy.

If a customer needs a bigger machine, a different region, or different storage, that's just different inputs to the same Terraform code. We never duplicate the modules themselves.

For upgrades, you roll them out gradually. Dev first, check it works, then prod, then any other customer environments. Each step is just a PR with the new version number.

---

## 3️⃣ Reliability

Everything lives in Git. Nothing is configured by hand on a server somewhere. If you deleted the whole cluster right now you could rebuild it from scratch without calling anyone — just re-run Terraform and Ansible.

Before anything merges, CI checks it: secret scanning, YAML validation, Terraform plan, Ansible lint, manifest validation. After a deploy, a post-deploy verification pipeline confirms that the nodes are up, Flux has reconciled, Postgres is running, and the app is reachable.

You always see what Terraform is going to do before it does it. Apply only runs after someone has reviewed and approved. State locking means two people can't apply at the same time.

---

## 4️⃣ Security

🌐 **Network:** Restrict the Kubernetes API to known IPs. SSH is always a weak spot in CI/CD setups because runners often have dynamic IPs — key-only auth and a brute-force protection tool are the minimum. In production you'd avoid exposing SSH at all and use a tunneling solution instead.

🔒 **Data:** Use whatever encryption at rest the platform provides by default and make sure backup storage inherits the same. Passwords should never be typed by hand or stored anywhere a human can read them.

🏃 **Runtime:** Lock down the OS on first boot — disable root login, password auth, set up a host firewall. Use Kubernetes Pod Security policies to restrict what containers can do. In production, pin images to a digest so you know exactly what's running.

🔑 **Secrets:** Nothing sensitive in Git, ever — run secret scanning on every PR. Secrets should flow automatically: generated at provisioning time, stored in a secrets manager, pulled into the cluster by an operator, consumed by pods by name. No human in the loop.

👤 **Access:** CI should authenticate to cloud providers without stored credentials — use short-lived tokens or federated identity. Scope secrets and permissions per environment so lower environments can't touch production.

📦 **Supply chain:** Pin third-party dependencies — Actions, collections, container images — to specific versions. In production, mirror images to a private registry and scan them before use.

> 🔧 For example, in GCP we would:
> - Restrict the Kubernetes API (6443) to the operator's CIDR via VPC firewall; replace SSH with Cloud IAP tunneling in production
> - Rely on Google-managed encryption at rest for GCE disks and GCS buckets; store all passwords in Secret Manager and pull them with External Secrets Operator
> - Harden nodes via Ansible and use Pod Security Admission; in production tighten policies per namespace
> - Run secret scanning on every PR with gitleaks; secrets flow from Terraform → Secret Manager → ESO → Kubernetes Secret
> - Authenticate CI to GCP via Workload Identity Federation — no keys stored anywhere; scope GitHub secrets per environment
> - Pin GitHub Actions to version tags; pin Ansible Galaxy collections in requirements.yml; in production mirror images to Artifact Registry with scanning
