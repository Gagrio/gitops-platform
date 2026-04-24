terraform {
  required_version = ">= 1.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Remote state in GCS — bucket must be pre-created before terraform init
  # Run: gcloud storage buckets create gs://<project-id>-tfstate --location=<region>
  backend "gcs" {
    bucket = "REPLACE_WITH_YOUR_PROJECT_ID-tfstate"
    prefix = "environments/dev"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
