# GCS bucket for CloudNativePG WAL archiving and base backups
resource "google_storage_bucket" "backup" {
  name     = "${var.environment}-${var.project_id}-pg-backups"
  location = var.region
  project  = var.project_id

  # Required for clean terraform destroy — GCP refuses to delete non-empty buckets
  force_destroy = true

  # Versioning for backup object safety
  versioning {
    enabled = true
  }

  # Auto-delete old backup objects beyond the retention window
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = var.retention_days
    }
  }
}

# Grant the node service account write access to the backup bucket
resource "google_storage_bucket_iam_member" "backup_writer" {
  bucket = google_storage_bucket.backup.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.service_account_email}"
}
