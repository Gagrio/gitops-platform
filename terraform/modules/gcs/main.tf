# Module: gcs
# GCS bucket used by CloudNativePG for WAL archiving and scheduled base backups.
# force_destroy is enabled so terraform destroy completes cleanly without manual
# bucket emptying. Lifecycle rules purge objects beyond the retention window.

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

# Grant the node SA full object access (create, delete, list, get) for WAL archiving and backups
resource "google_storage_bucket_iam_member" "backup_writer" {
  bucket = google_storage_bucket.backup.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.service_account_email}"
}

# barman-cloud calls storage.buckets.get to verify the bucket before archiving;
# storage.objectAdmin does not include bucket-level permissions so this is required separately.
resource "google_storage_bucket_iam_member" "backup_bucket_reader" {
  bucket = google_storage_bucket.backup.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${var.service_account_email}"
}
