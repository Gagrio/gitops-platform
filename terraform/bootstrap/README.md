# 🔑 Bootstrap

This module runs **once**, manually, before CI exists. It creates the GCP identity that CI will use and populates GitHub Actions secrets automatically — so that every subsequent Terraform run happens in CI, not on your laptop.

## 🏗️ What it creates

- ✅ All required GCP APIs enabled
- 🤖 CI service account with least-privilege IAM roles (no `roles/editor` — only what Terraform actually needs)
- 🔐 Workload Identity Federation — GitHub Actions authenticates to GCP with short-lived OIDC tokens, no stored credentials
- 🔒 GitHub Actions secrets for all non-sensitive config values (project ID, region, WIF provider, state bucket, admin CIDR, SSH public key)

## 🚫 What it does NOT do

- Generate the SSH private key — that's created locally with `ssh-keygen` and added to GitHub secrets manually. It must never enter Terraform state.
- Generate Postgres passwords — those are handled by `random_password` in the main environment Terraform and stored directly in Secret Manager.

## 📋 Prerequisites

Before running this module:

1. The GCS state bucket must already exist (one `gcloud` command — see the [Deployment Guide](../../Documentation/Deployment%20guide.md))
2. You must be authenticated with personal GCP credentials (`gcloud auth application-default login`)
3. You must have a GitHub personal access token with `repo` scope

## 🚀 Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# fill in terraform.tfvars

terraform init -backend-config="bucket=<your-state-bucket-name>"
terraform apply
```

After `terraform apply` completes, add the SSH private key to GitHub secrets manually — see Step 1.6 of the [Deployment Guide](../../Documentation/Deployment%20guide.md).

## 🗄️ Backend

Uses the same GCS bucket as all other environments, under the `bootstrap` prefix. The bucket is created manually before this module runs, so there's no chicken-and-egg dependency. All Terraform state lives in one place.
