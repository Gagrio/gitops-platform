# Bootstrap module
# Uses a local backend — runs once before the GCS state bucket exists.
# This file is the only Terraform config that runs with personal credentials.
# After this, CI takes over all further Terraform runs.
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

  backend "local" {}
}

provider "google" {
  project = var.project_id
}

provider "github" {
  token = var.github_token
  owner = var.github_owner
}
