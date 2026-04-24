# Bootstrap module
# Runs once with the operator's personal credentials to wire up CI.
# Uses the same GCS backend as all other environments — the state bucket is
# created manually (one gcloud command) before this module runs, so it is
# available here. Storing bootstrap state in GCS is safer than storing it
# locally and keeps all Terraform state in one place.
terraform {
  required_version = ">= 1.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }

  # Bucket name passed at init time — same bucket as all other environments
  #   terraform init -backend-config="bucket=<your-bucket-name>"
  backend "gcs" {
    prefix = "bootstrap"
  }
}

provider "google" {
  project = var.project_id
}

provider "github" {
  token = var.github_token
  owner = var.github_owner
}
