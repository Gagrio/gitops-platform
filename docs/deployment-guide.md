# Deployment Guide

This guide walks you through deploying the full platform from scratch into your Google Cloud account. Follow each step in order. By the end you will have a running Kubernetes cluster with a managed PostgreSQL database, GitOps-driven deployments via Flux, automated backups to GCS, and a monitoring stack accessible from your browser.

Estimated total time: **30–45 minutes** (most of it waiting for provisioning).

---

## Prerequisites

### Tools

Install the following tools before starting. Click the install link for instructions for your OS.

| Tool | Min version | Install |
|---|---|---|
| `gcloud` CLI | any recent | https://cloud.google.com/sdk/docs/install |
| Terraform | >= 1.7 | https://developer.hashicorp.com/terraform/install |
| Ansible | >= 2.14 | https://docs.ansible.com/ansible/latest/installation_guide |
| `kubectl` | >= 1.28 | https://kubernetes.io/docs/tasks/tools |
| `flux` CLI | >= 2.0 | https://fluxcd.io/flux/installation/#install-the-flux-cli |

Verify everything is installed:

```bash
gcloud version
terraform version
ansible --version
kubectl version --client
flux version
```

### Accounts and access

You also need the following before starting:

**A GCP account with billing enabled.** If you do not have one, create it at https://console.cloud.google.com. A new account comes with $300 in free credits which is more than enough for this deployment.

**A GCP project.** Create one at https://console.cloud.google.com/projectcreate or use an existing one. Note the project ID (not the project name — it looks like `my-project-123456`).

**An SSH key pair.** This is used by Ansible to connect to the nodes. Check if you already have one:
```bash
ls ~/.ssh/id_rsa.pub
```
If the file does not exist, generate a new key pair:
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
# Press Enter twice to leave the passphrase empty
```

**A GitHub personal access token.** Flux uses this to read and write to the repository. Create one at https://github.com/settings/tokens — click **Generate new token (classic)**, give it a name, and tick the `repo` scope. Copy the token value — you will need it in Step 3.

---

## Step 1 — GCP Project Setup

### 1.1 Authenticate with GCP

Run both commands below. The first logs you into the GCP Console. The second sets up credentials that Terraform will use to create resources.

```bash
gcloud auth login
gcloud auth application-default login
```

Both will open a browser window asking you to sign in with your Google account. After completing both, set your project:

```bash
gcloud config set project <your-project-id>
```

Replace `<your-project-id>` with your actual project ID (e.g. `my-project-123456`). Verify it is set correctly:

```bash
gcloud config get project
```

### 1.2 Enable required GCP APIs

GCP disables most APIs by default. Run the following to enable the services this platform uses:

```bash
gcloud services enable \
  compute.googleapis.com \
  secretmanager.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com
```

- `compute` — virtual machines and networking
- `secretmanager` — stores Postgres credentials securely
- `storage` — GCS bucket for database backups
- `iam` + `iamcredentials` — service accounts and Workload Identity

This takes about 30 seconds. You will see `Operation finished successfully` for each service.

### 1.3 Create the Terraform state bucket

Terraform stores a record of what it has created in a remote state file. This state file lives in a GCS bucket that must exist before Terraform can run. Create it now:

```bash
gcloud storage buckets create gs://<your-bucket-name> \
  --location=europe-west1 \
  --uniform-bucket-level-access
```

Choose a name that is globally unique across all of GCP (e.g. `myname-enclaive-tfstate`). The location should match the region you plan to deploy into. Make a note of the bucket name — you will need it in Step 2.

---

## Step 2 — Configure Terraform

### 2.1 Clone the repository

```bash
git clone https://github.com/<your-github-username>/enclaive-platform-challenge.git
cd enclaive-platform-challenge
```

### 2.2 Set your variables

```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` in a text editor and fill in each value. Here is where each one comes from:

---

**`project_id`** — Your GCP project ID. Find it with:
```bash
gcloud projects list
```

---

**`region` and `zone`** — Where your VMs will be created. The defaults (`europe-west1` / `europe-west1-b`) are a good choice for European users. For other regions see https://cloud.google.com/compute/docs/regions-zones. Make sure the zone belongs to the region you choose (e.g. if region is `us-central1`, zone could be `us-central1-a`).

---

**`admin_cidr`** — Your current public IP address. This restricts SSH and Kubernetes API access so that only your machine can reach the cluster. Find your IP with:
```bash
curl ifconfig.me
```
Then append `/32` to make it a single-host CIDR range. For example if your IP is `203.0.113.10`, the value is `203.0.113.10/32`.

> Do not use `0.0.0.0/0` here — that would expose SSH and the Kubernetes API to the entire internet.

---

**`ssh_public_key`** — The public half of your SSH key pair. Terraform injects this into the VMs so Ansible can connect. Print it with:
```bash
cat ~/.ssh/id_rsa.pub
```
Copy the entire line (starts with `ssh-rsa`) into the tfvars file.

---

**`pg_superuser_password`**, **`pg_app_password`**, **`pg_replication_password`** — Passwords for three Postgres users that CloudNativePG creates:
- `pg_superuser_password` — the `postgres` admin user
- `pg_app_password` — the application user Adminer connects with
- `pg_replication_password` — internal replication between primary and replicas

Generate a strong random password for each:
```bash
openssl rand -base64 24
```
Run the command three times and use a different value for each.

> These passwords are stored in Google Secret Manager by Terraform and never written to disk or committed to Git. The `terraform.tfvars` file is gitignored.

---

### 2.3 Initialise Terraform

Run this from inside `terraform/environments/dev/`. Use the same bucket name you created in Step 1.3:

```bash
terraform init -backend-config="bucket=<your-bucket-name>"
```

You should see `Terraform has been successfully initialized!` at the end.

### 2.4 Review the plan

```bash
terraform plan
```

Terraform will print everything it intends to create. Review the list and confirm it matches what you expect. You should see:
- 1 VPC and 1 subnet
- 3 GCE virtual machines (`dev-node-01`, `dev-node-02`, `dev-node-03`), each with a reserved static internal IP
- 1 GCS bucket for PostgreSQL backups
- 1 GCP service account with scoped IAM permissions
- 3 secrets in Google Secret Manager (Postgres credentials)
- 4 VPC firewall rules

If there are any errors (e.g. an API not enabled, or an invalid project ID), fix them before continuing.

### 2.5 Apply

```bash
terraform apply
```

Terraform will print the plan again and ask for confirmation. Type `yes` and press Enter.

This takes approximately 2–3 minutes. When complete, it will print the outputs:

```bash
terraform output
```

You will see the external and internal IPs for all three nodes. Keep this terminal open or copy the IPs — you will need them in the next step.

---

## Step 3 — Bootstrap the Cluster

Ansible connects to the three nodes over SSH and runs a sequence of steps:
1. Configures the OS — installs packages, sets kernel parameters, installs containerd
2. Installs k3s and forms a 3-node Kubernetes cluster
3. Hardens the nodes — firewall, disabled services, security baselines
4. Installs Flux and connects it to this GitHub repository

By the end of this step, the cluster is running and Flux has already started deploying everything defined in `gitops/`.

### 3.1 Configure the inventory

Navigate back to the repo root and set up the Ansible inventory file:

```bash
cd ../../../ansible
cp inventory/hosts.example.yml inventory/hosts.yml
```

Open `inventory/hosts.yml` and replace the IP placeholders with the external IPs from your `terraform output`:

```yaml
all:
  children:
    control:
      hosts:
        dev-node-01:
          ansible_host: <external-ip-of-node-01>   # from terraform output
    workers:
      hosts:
        dev-node-02:
          ansible_host: <external-ip-of-node-02>   # from terraform output
        dev-node-03:
          ansible_host: <external-ip-of-node-03>   # from terraform output
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: ~/.ssh/id_rsa
```

> `ansible_user` must be `ubuntu` — this matches the OS image used by Terraform. `ansible_ssh_private_key_file` must point to the private key that corresponds to the public key you put in `terraform.tfvars`.

### 3.2 Set Flux environment variables

Flux needs access to your GitHub repository to read manifests and commit its own configuration. Set these variables in your terminal before running the playbook:

```bash
export GITHUB_TOKEN=<your-github-personal-access-token>   # from the Prerequisites step
export GITHUB_USER=<your-github-username>
export GITHUB_REPO=enclaive-platform-challenge
```

### 3.3 Verify Ansible can reach the nodes

Before running the full playbook, confirm Ansible can connect to all three nodes:

```bash
ansible all -i inventory/hosts.yml -m ping
```

All three nodes should respond with `pong`. If a node fails, check:
- The IP address is correct in `hosts.yml`
- Your SSH key matches what was injected by Terraform
- Your `admin_cidr` in tfvars includes your current IP (it may have changed)

### 3.4 Run the bootstrap playbook

```bash
ansible-playbook playbooks/bootstrap.yml -i inventory/hosts.yml
```

The playbook runs four roles across all nodes in sequence. Expect this to take 5–10 minutes. You will see task-by-task output as it progresses. A successful run ends with a `PLAY RECAP` showing no `failed` tasks.

### 3.5 Verify the cluster

The playbook writes a kubeconfig file to your local machine. Load it:

```bash
export KUBECONFIG=~/.kube/config-enclaive-dev
```

Check that all three nodes are ready:

```bash
kubectl get nodes
```

Expected output:
```
NAME           STATUS   ROLES                  AGE   VERSION
dev-node-01   Ready    control-plane,master   2m    v1.x.x+k3s1
dev-node-02   Ready    <none>                 1m    v1.x.x+k3s1
dev-node-03   Ready    <none>                 1m    v1.x.x+k3s1
```

Then check that Flux is running:

```bash
flux check
```

All checks should pass. Then confirm Flux has connected to the repository:

```bash
flux get sources git -A
```

The `GitRepository` should show `Fetched revision` and `True` in the Ready column.

---

## Step 4 — Watch GitOps Reconcile

Flux polls the repository every 60 seconds and applies any changes it finds. After the bootstrap it will automatically install all platform components in order:

1. **Infrastructure controllers** — CloudNativePG operator, External Secrets Operator, Prometheus stack
2. **PostgreSQL cluster** — 3-instance HA cluster with backups and monitoring configured
3. **Adminer** — a lightweight database UI to verify end-to-end connectivity

Watch the reconciliation progress live:

```bash
flux get kustomizations -A --watch
```

You will see each kustomization move from `Progressing` to `Applied revision`. Wait until all of them show `True` in the Ready column before moving to Step 5. This takes approximately 5–10 minutes depending on image pull times.

If any kustomization stays in a failed state, inspect it with:

```bash
flux logs --kind=Kustomization --name=<name> -n flux-system
```

---

## Step 5 — Verify the Platform

Once all kustomizations are ready, verify each component of the platform.

### 5.1 PostgreSQL cluster

```bash
kubectl get cluster -n postgres
```

The `STATUS` column should show `Cluster in healthy state`. Then confirm all three pods are running:

```bash
kubectl get pods -n postgres
```

Expected output:
```
NAME     READY   STATUS    RESTARTS   AGE
pg-1-1   1/1     Running   0          5m
pg-2-1   1/1     Running   0          4m
pg-3-1   1/1     Running   0          4m
```

### 5.2 Backups

Confirm the scheduled backup configuration is in place:

```bash
kubectl get scheduledbackup -n postgres
```

The first automated backup runs on the schedule defined in the cluster configuration (daily at 02:00 UTC). You can trigger a manual backup immediately to verify it works:

```bash
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: manual-test
  namespace: postgres
spec:
  cluster:
    name: postgres-cluster
EOF

kubectl get backup -n postgres
```

The backup status should move to `Completed` within a few minutes.

### 5.3 Monitoring

Check that the monitoring stack is up:

```bash
kubectl get pods -n monitoring
```

All pods should be Running. Access Grafana in your browser by port-forwarding:

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
```

Open http://localhost:3000. The default login is:
- **Username**: `admin`
- **Password**: `prom-operator`

> This is the default for the kube-prometheus-stack Helm chart. In a production setup this should be changed.

Navigate to **Dashboards → CloudNativePG** to see PostgreSQL cluster metrics (replication lag, connections, WAL activity).

### 5.4 Adminer (database UI)

```bash
kubectl port-forward svc/adminer 8080:80 -n demo-app
```

Open http://localhost:8080 and fill in the connection form:

| Field | Value |
|---|---|
| System | PostgreSQL |
| Server | `postgres-rw.postgres.svc.cluster.local` |
| Username | `app` |
| Password | the value you set for `pg_app_password` in tfvars |
| Database | `app` |

Click **Login**. You should reach the Adminer database interface connected to the live PostgreSQL cluster. This confirms the full stack is working end-to-end.

---

## Step 6 — Making Changes

All cluster configuration is managed through Git. The workflow for any change is:

1. Edit the relevant file under `gitops/`
2. Commit and push to a branch
3. Open a pull request — CI will validate the manifests automatically
4. Merge after review
5. Flux detects the change within 60 seconds and applies it to the cluster

> Never run `kubectl apply` directly against the cluster. Any manual change will be overwritten by Flux on the next reconcile loop.

---

## Step 7 — Teardown

When you are done testing, destroy all GCP resources to stop incurring costs:

```bash
cd terraform/environments/dev
terraform destroy
```

Terraform will print a list of everything it will delete and ask for confirmation. Type `yes` and press Enter. This takes 2–3 minutes.

The GCS backup bucket is configured with `force_destroy = true`, so Terraform will empty and delete it automatically — no manual cleanup needed.

The **Terraform state bucket** (the one you created in Step 1.3) is not managed by Terraform itself. Delete it manually when you are done:

```bash
gcloud storage rm -r gs://<your-bucket-name>
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `terraform apply` fails with permission error | APIs not enabled or ADC not set | Re-run Steps 1.1 and 1.2 |
| Ansible ping fails | Wrong IP, wrong SSH key, or IP not in `admin_cidr` | Check tfvars `admin_cidr` matches current IP |
| Node not `Ready` after playbook | k3s failed to start | SSH into node and run `sudo systemctl status k3s` |
| Flux kustomization stuck `Progressing` | Image pull taking long or resource not ready | Wait a few more minutes, then check `flux logs` |
| Adminer login fails | Wrong password or wrong service address | Confirm `pg_app_password` in tfvars and service name |
