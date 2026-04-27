# Module: iam
# Dedicated GCP service account for cluster nodes with minimal permissions.
# Workload Identity bindings allow the External Secrets Operator and CloudNativePG
# to authenticate to GCP APIs without storing long-lived credentials in the cluster.

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

