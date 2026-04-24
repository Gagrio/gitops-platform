terraform {
  required_version = ">= 1.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "REPLACE_WITH_YOUR_PROJECT_ID-tfstate"
    prefix = "environments/prod"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
