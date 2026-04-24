# Dedicated service account for GCE nodes — principle of least privilege
resource "google_service_account" "nodes" {
  account_id   = "${var.environment}-k8s-nodes"
  display_name = "${var.environment} Kubernetes Nodes"
  project      = var.project_id
}

# Allow nodes to read secrets from Secret Manager (used by External Secrets Operator)
resource "google_project_iam_member" "secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# Allow nodes to write logs to Cloud Logging
resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# Allow nodes to write metrics to Cloud Monitoring
resource "google_project_iam_member" "metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# Workload Identity pool — links GCP SA to the Kubernetes cluster's identity namespace
resource "google_service_account_iam_member" "workload_identity_eso" {
  service_account_id = google_service_account.nodes.name
  role               = "roles/iam.workloadIdentityUser"
  # Allows the External Secrets Operator k8s SA to impersonate this GCP SA
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets]"
}

resource "google_service_account_iam_member" "workload_identity_cnpg" {
  service_account_id = google_service_account.nodes.name
  role               = "roles/iam.workloadIdentityUser"
  # Allows the CloudNativePG backup SA to impersonate this GCP SA for GCS writes
  member             = "serviceAccount:${var.project_id}.svc.id.goog[postgres/postgres-backup]"
}
