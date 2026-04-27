terraform {
  required_version = ">= 1.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Partial backend config — bucket name is passed at init time, not hardcoded.
  # The bucket must be created manually before running terraform init:
  #
  #   gcloud storage buckets create gs://<your-bucket-name> --location=<region>
  #
  # Then initialise with:
  #
  #   terraform init -backend-config="bucket=<your-bucket-name>"
  backend "gcs" {
    prefix = "environments/prod"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
