# Deployment Guide

This guide walks you through deploying the full platform from scratch into your Google Cloud account. By the end you will have a running Kubernetes cluster with a managed PostgreSQL database, GitOps-driven deployments via Flux, automated backups to GCS, and a monitoring stack.

---

## Prerequisites

Install the following tools before starting:

| Tool | Min version | Install |
|---|---|---|
| `gcloud` CLI | any recent | https://cloud.google.com/sdk/docs/install |
| Terraform | >= 1.7 | https://developer.hashicorp.com/terraform/install |
| Ansible | >= 2.14 | `pip install ansible` |
| `kubectl` | >= 1.28 | https://kubernetes.io/docs/tasks/tools |
| `flux` CLI | >= 2.0 | https://fluxcd.io/flux/installation/#install-the-flux-cli |

You also need:
- A **GCP account** with billing enabled
- A **GCP project** (existing or new)
- An **SSH key pair** — if you don't have one: `ssh-keygen -t rsa -b 4096`
- A **GitHub personal access token** with `repo` scope — Flux uses this to read the repository

---

## Step 1 — GCP Project Setup

### 1.1 Authenticate

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project <your-project-id>
```

### 1.2 Enable required APIs

```bash
gcloud services enable \
  compute.googleapis.com \
  secretmanager.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com
```

### 1.3 Create the Terraform state bucket

The state bucket must exist before Terraform can initialise. Choose a globally unique name.

```bash
gcloud storage buckets create gs://<your-bucket-name> \
  --location=europe-west1 \
  --uniform-bucket-level-access
```

---

## Step 2 — Configure Terraform

### 2.1 Set your variables

```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and fill in your values. Here is where each one comes from:

**`project_id`** — Your GCP project ID. Find it in the GCP Console under the project selector, or run:
```bash
gcloud projects list
```

**`region` and `zone`** — The GCP region and zone to deploy into. Defaults to `europe-west1` / `europe-west1-b`. See the full list at https://cloud.google.com/compute/docs/regions-zones. Pick a region geographically close to you.

**`admin_cidr`** — Your current public IP address in CIDR notation. This restricts SSH and Kubernetes API access to your machine only. Find your IP with:
```bash
curl ifconfig.me
# append /32 to make it a host CIDR, e.g. 203.0.113.10/32
```

**`ssh_public_key`** — The public key Terraform injects into the nodes so Ansible can SSH in. Use your existing key or generate one:
```bash
# Generate a new key (skip if you already have one)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa

# Print the public key to copy into tfvars
cat ~/.ssh/id_rsa.pub
```

**`pg_superuser_password`** — Password for the PostgreSQL superuser (`postgres`). Used for admin operations. Use a strong random value:
```bash
openssl rand -base64 24
```

**`pg_app_password`** — Password for the application user that Adminer and your workloads connect with. Generate the same way.

**`pg_replication_password`** — Password for the replication user CloudNativePG uses for streaming replication between primary and replicas. Generate the same way.

> These passwords are stored in Google Secret Manager by Terraform and never written to disk or committed to Git. The `terraform.tfvars` file itself is gitignored.

### 2.2 Initialise Terraform

```bash
terraform init -backend-config="bucket=<your-bucket-name>"
```

### 2.3 Review the plan

```bash
terraform plan
```

Review the output. Terraform will create:
- 1 VPC + 1 subnet
- 3 GCE instances (`dev-node-01`, `dev-node-02`, `dev-node-03`) each with a reserved static internal IP
- 1 GCS bucket for PostgreSQL backups
- 1 GCP service account with scoped IAM permissions
- 3 secrets in Google Secret Manager (Postgres credentials)
- VPC firewall rules

### 2.4 Apply

```bash
terraform apply
```

This takes approximately 2–3 minutes. When complete, note the outputs:

```bash
terraform output
```

You will see the internal and external IPs for all three nodes. You will need these in the next step.

---

## Step 3 — Bootstrap the Cluster

Ansible connects to the three nodes over SSH and:
1. Configures the OS (packages, kernel parameters, containerd)
2. Installs k3s and forms the cluster
3. Hardens the nodes
4. Installs Flux and connects it to this repository

### 3.1 Configure the inventory

Copy the example inventory and fill in the external IPs from your Terraform output:

```bash
cd ../../../ansible
cp inventory/hosts.example.yml inventory/hosts.yml
```

Edit `inventory/hosts.yml`:

```yaml
all:
  children:
    control:
      hosts:
        dev-node-01:
          ansible_host: <external-ip-of-node-01>
    workers:
      hosts:
        dev-node-02:
          ansible_host: <external-ip-of-node-02>
        dev-node-03:
          ansible_host: <external-ip-of-node-03>
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: ~/.ssh/id_rsa
```

### 3.2 Set Flux environment variables

Flux needs your GitHub token and repository details to bootstrap:

```bash
export GITHUB_TOKEN=<your-github-personal-access-token>
export GITHUB_USER=<your-github-username>
```

### 3.3 Run the bootstrap playbook

```bash
ansible-playbook playbooks/bootstrap.yml -i inventory/hosts.yml
```

The playbook runs four roles in sequence across all nodes. Expect this to take 5–10 minutes.

When it completes, Flux is running inside the cluster and has already begun reconciling the `gitops/` directory from this repository.

### 3.4 Verify the cluster

The playbook writes a kubeconfig to your local machine at `~/.kube/config-enclaive-dev`. Point kubectl at it:

```bash
export KUBECONFIG=~/.kube/config-enclaive-dev
kubectl get nodes
```

All three nodes should show `Ready`. Then check Flux:

```bash
flux check
flux get all -A
```

---

## Step 4 — Watch GitOps Reconcile

Flux reconciles the repository every 60 seconds. After the bootstrap, it will automatically install:

1. **Infrastructure controllers** — CloudNativePG operator, External Secrets Operator, Prometheus stack
2. **PostgreSQL cluster** — 3-instance HA cluster with backups and monitoring
3. **Adminer** — database UI to verify end-to-end connectivity

You can watch the reconciliation live:

```bash
flux get kustomizations -A --watch
```

Wait until all kustomizations show `Applied revision` and `True` in the Ready column. This takes approximately 5–10 minutes depending on image pull times.

---

## Step 5 — Verify the Platform

### PostgreSQL cluster

```bash
kubectl get cluster -n postgres
kubectl get pods -n postgres
```

You should see `pg-1`, `pg-2`, `pg-3` all Running. The cluster status should show `Cluster in healthy state`.

### Backups

```bash
kubectl get scheduledbackup -n postgres
kubectl get backup -n postgres
```

### Monitoring

```bash
kubectl get pods -n monitoring
```

Access Grafana by port-forwarding:

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
```

Open http://localhost:3000 — default credentials are in the Prometheus stack Helm values.

### Adminer

```bash
kubectl port-forward svc/adminer 8080:80 -n demo-app
```

Open http://localhost:8080 and connect using:
- **System**: PostgreSQL
- **Server**: `postgres-rw.postgres.svc.cluster.local`
- **Username**: the app username from your tfvars
- **Password**: the app password from your tfvars

---

## Step 6 — Making Changes

All cluster configuration is managed through Git. To make a change:

1. Edit the relevant file under `gitops/`
2. Open a pull request
3. Merge after review
4. Flux detects the change within 60 seconds and reconciles

Never run `kubectl apply` directly against the cluster.

---

## Step 7 — Teardown

When you are done, destroy all resources cleanly:

```bash
cd terraform/environments/dev
terraform destroy
```

> The GCS backup bucket has `force_destroy = true` set, so Terraform will empty and delete it automatically. The Terraform state bucket is **not** managed by Terraform and must be deleted manually if desired:
> ```bash
> gcloud storage rm -r gs://<your-bucket-name>
> ```
