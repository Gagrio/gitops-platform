# Deployment Guide

## How This Works

User intervention is kept to a minimum. There are three tiers of automation:

| Tier | Who does it | When |
|---|---|---|
| **One-time bootstrap** | You, manually | Once, before CI is wired up |
| **Infrastructure deploy** | GitHub Actions CI | On every merge to `main` that touches `terraform/` or `ansible/` |
| **Application changes** | Flux (automatic) | Every 60 seconds, continuously |

After the one-time bootstrap is complete, the normal workflow is: **open a PR → merge → CI and Flux handle the rest**. You do not run Terraform or Ansible manually.

---

## Part 1 — One-Time Bootstrap

These steps are done once to wire up the automation. After this, CI takes over.

### Prerequisites

You need the following tools installed locally only for the bootstrap steps:

| Tool | Min version | Install |
|---|---|---|
| `gcloud` CLI | any recent | https://cloud.google.com/sdk/docs/install |
| `kubectl` | >= 1.28 | https://kubernetes.io/docs/tasks/tools |
| `flux` CLI | >= 2.0 | https://fluxcd.io/flux/installation/#install-the-flux-cli |

Terraform and Ansible are only needed if you want to run the deploy locally. In normal use, CI runs them for you.

---

### 1.1 GCP Authentication

```bash
gcloud auth login
gcloud config set project <your-project-id>
```

This opens a browser window to sign in with your Google account. Replace `<your-project-id>` with your GCP project ID — find it with `gcloud projects list`.

---

### 1.2 Enable Required GCP APIs

```bash
gcloud services enable \
  compute.googleapis.com \
  secretmanager.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com
```

This takes about 30 seconds. Each service prints `Operation finished successfully` when done.

---

### 1.3 Create the Terraform State Bucket

Terraform stores its state in GCS. This bucket must exist before CI can run `terraform init`. Create it once:

```bash
export PROJECT_ID=$(gcloud config get project)
export REGION=europe-west1

gcloud storage buckets create gs://${PROJECT_ID}-tfstate \
  --location=${REGION} \
  --uniform-bucket-level-access
```

Note the bucket name (`<project-id>-tfstate`) — you will need it when configuring GitHub secrets.

---

### 1.4 Create a CI Service Account

CI needs a GCP identity to run Terraform. Create a dedicated service account for this:

```bash
gcloud iam service-accounts create ci-deployer \
  --display-name="CI Deployer"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:ci-deployer@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/editor"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:ci-deployer@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/secretmanager.admin"
```

> `roles/editor` is used here for simplicity. In production this should be tightened to only the specific roles Terraform needs.

---

### 1.5 Set Up Workload Identity Federation

Workload Identity Federation allows GitHub Actions to authenticate to GCP without storing a service account key. This is the recommended approach — no long-lived credentials stored in GitHub.

```bash
export PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")
export GITHUB_USER=<your-github-username>
export GITHUB_REPO=enclaive-platform-challenge

# Create the Workload Identity Pool
gcloud iam workload-identity-pools create "github-actions" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --display-name="GitHub Actions"

# Create the OIDC provider that trusts GitHub's token issuer
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="github-actions" \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Allow GitHub Actions in your specific repo to impersonate the CI service account
gcloud iam service-accounts add-iam-policy-binding \
  "ci-deployer@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions/attribute.repository/${GITHUB_USER}/${GITHUB_REPO}"
```

Note the Workload Identity Provider resource name — you need it for GitHub secrets:
```bash
echo "projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions/providers/github-provider"
```

---

### 1.6 Generate an SSH Key Pair for CI

CI needs to SSH into the nodes to run Ansible. Generate a dedicated key pair for this (do not reuse your personal key):

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/enclaive-ci -N ""
```

This creates two files:
- `~/.ssh/enclaive-ci` — the private key (goes into GitHub secrets)
- `~/.ssh/enclaive-ci.pub` — the public key (goes into Terraform variables)

---

### 1.7 Generate Postgres Passwords

Generate three strong passwords — one for each Postgres user:

```bash
openssl rand -base64 24  # pg_superuser_password
openssl rand -base64 24  # pg_app_password
openssl rand -base64 24  # pg_replication_password
```

Save these somewhere secure (e.g. a password manager). You will enter them as GitHub secrets.

---

### 1.8 Configure GitHub Secrets

Go to your repository on GitHub → **Settings → Secrets and variables → Actions → New repository secret**.

Add the following secrets:

| Secret name | Value |
|---|---|
| `GCP_PROJECT_ID` | Your GCP project ID |
| `GCP_SERVICE_ACCOUNT` | `ci-deployer@<project-id>.iam.gserviceaccount.com` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | The provider resource name from Step 1.5 |
| `TF_STATE_BUCKET` | The bucket name from Step 1.3 (e.g. `<project-id>-tfstate`) |
| `ADMIN_CIDR` | Your public IP in CIDR notation — find it with `curl ifconfig.me`, append `/32` |
| `SSH_PUBLIC_KEY` | Contents of `~/.ssh/enclaive-ci.pub` |
| `SSH_PRIVATE_KEY` | Contents of `~/.ssh/enclaive-ci` |
| `PG_SUPERUSER_PASSWORD` | First password from Step 1.7 |
| `PG_APP_PASSWORD` | Second password from Step 1.7 |
| `PG_REPLICATION_PASSWORD` | Third password from Step 1.7 |

---

### 1.9 Fork and Configure the Repository

If you have not already, fork this repository to your own GitHub account. Then clone it locally:

```bash
git clone https://github.com/<your-github-username>/enclaive-platform-challenge.git
cd enclaive-platform-challenge
```

---

## Part 2 — Deploy

With the bootstrap complete, deploying is a single Git operation.

### 2.1 Trigger the First Deploy

Push or merge any change to `main` that touches `terraform/` or `ansible/`. The CI pipeline will:

1. **Validate** — run `terraform fmt`, `terraform validate`, `terraform plan`, `ansible-lint`, and `kubeconform` on the PR
2. **Apply** — on merge to `main`, run `terraform apply` to provision all GCP infrastructure
3. **Bootstrap** — run `ansible-playbook bootstrap.yml` to install k3s and Flux on the nodes

Watch the pipeline run in **GitHub → Actions**.

### 2.2 Monitor CI Progress

The CI run takes approximately 10–15 minutes end-to-end:

- `terraform apply` — ~3 minutes (VMs, networking, GCS, IAM, secrets)
- `ansible-playbook` — ~8 minutes (OS config, k3s, hardening, Flux bootstrap)

When the CI job completes successfully, Flux is running inside the cluster and has already started reconciling `gitops/`. From this point, all further changes are applied by Flux automatically — no more CI jobs needed for application changes.

---

## Part 3 — Verify

After CI completes, retrieve the kubeconfig that the Ansible playbook wrote to the CI artifacts (or generate it locally — see [Running Locally](#running-locally)):

```bash
export KUBECONFIG=~/.kube/config-enclaive-dev
```

### 3.1 Check the cluster

```bash
kubectl get nodes
```

Expected output:
```
NAME           STATUS   ROLES                  AGE   VERSION
dev-node-01   Ready    control-plane,master   5m    v1.x.x+k3s1
dev-node-02   Ready    <none>                 4m    v1.x.x+k3s1
dev-node-03   Ready    <none>                 4m    v1.x.x+k3s1
```

### 3.2 Watch Flux reconcile

```bash
flux get kustomizations -A --watch
```

Wait until all kustomizations show `True` in the Ready column. This takes 5–10 minutes after the cluster is up. Flux installs everything in order:

1. Infrastructure controllers (CloudNativePG operator, External Secrets Operator, Prometheus stack)
2. PostgreSQL cluster (3-instance HA, backups, monitoring)
3. Adminer (database UI)

If a kustomization stays in a failed state, inspect it:
```bash
flux logs --kind=Kustomization --name=<name> -n flux-system
```

### 3.3 Verify PostgreSQL

```bash
kubectl get cluster -n postgres
kubectl get pods -n postgres
```

The cluster status should show `Cluster in healthy state` and all three pods (`pg-1`, `pg-2`, `pg-3`) should be `Running`.

### 3.4 Access Grafana

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
```

Open http://localhost:3000. Default credentials: **admin / prom-operator**. Navigate to **Dashboards → CloudNativePG** for PostgreSQL metrics.

### 3.5 Access Adminer

```bash
kubectl port-forward svc/adminer 8080:80 -n demo-app
```

Open http://localhost:8080 and connect with:

| Field | Value |
|---|---|
| System | PostgreSQL |
| Server | `postgres-rw.postgres.svc.cluster.local` |
| Username | `app` |
| Password | the value of `PG_APP_PASSWORD` from your GitHub secrets |
| Database | `app` |

A successful login confirms the full stack is working end-to-end.

---

## Part 4 — Day-to-Day Operations

After the initial deploy, **you do not run Terraform or Ansible again** unless you are changing infrastructure. The normal workflow is:

**For application or cluster config changes** (anything under `gitops/`):
1. Edit the file
2. Push to a branch and open a PR
3. Merge — Flux picks up the change within 60 seconds

**For infrastructure changes** (anything under `terraform/` or `ansible/`):
1. Edit the file
2. Push to a branch and open a PR — CI runs `terraform plan` so you can review the impact
3. Merge — CI runs `terraform apply` and re-runs the Ansible playbook if needed

> Never run `kubectl apply` directly. Any manual change will be overwritten by Flux on the next reconcile.

---

## Running Locally

If you need to run Terraform or Ansible locally (e.g. for debugging), install the additional tools:

```bash
# Terraform >= 1.7
# https://developer.hashicorp.com/terraform/install

# Ansible >= 2.14
pip install ansible
```

Then run with your local GCP credentials:

```bash
gcloud auth application-default login

cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
# fill in terraform.tfvars

terraform init -backend-config="bucket=<your-state-bucket>"
terraform plan
terraform apply
```

For Ansible:
```bash
cd ansible
cp inventory/hosts.example.yml inventory/hosts.yml
# fill in node IPs from terraform output

export GITHUB_TOKEN=<your-github-token>
export GITHUB_USER=<your-github-username>
export GITHUB_REPO=enclaive-platform-challenge

ansible-playbook playbooks/bootstrap.yml -i inventory/hosts.yml
```

---

## Teardown

Destroy all GCP resources when you are done:

```bash
cd terraform/environments/dev
terraform destroy
```

Type `yes` when prompted. This takes 2–3 minutes. The GCS backup bucket is deleted automatically (`force_destroy = true`).

Delete the Terraform state bucket manually — it is not managed by Terraform:

```bash
gcloud storage rm -r gs://${PROJECT_ID}-tfstate
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| CI fails with GCP permission error | WIF not configured or wrong SA | Re-check Steps 1.4 and 1.5 |
| CI fails at `terraform apply` | Missing or wrong GitHub secret | Check all secrets in Step 1.8 are set correctly |
| CI fails at `ansible-playbook` | SSH key mismatch or node not reachable | Confirm `SSH_PUBLIC_KEY` and `SSH_PRIVATE_KEY` are the same key pair |
| Node not `Ready` | k3s failed to start | SSH into node: `sudo systemctl status k3s` |
| Flux kustomization stuck | Image pull slow or dependency not ready | Wait a few minutes, then: `flux logs --kind=Kustomization --name=<name> -n flux-system` |
| Adminer login fails | Wrong password | Confirm `PG_APP_PASSWORD` secret value matches what was applied by Terraform |
