# Environment: dev
# Wires all modules together for the development environment. Uses e2-standard-2 nodes,
# a 30-day backup retention window, and a /24 subnet at 10.0.0.0/24.
# Secrets for Postgres credentials are seeded into Google Secret Manager here
# and pulled into the cluster at runtime by the External Secrets Operator.

# VPC and subnet for the cluster
module "network" {
  source      = "../../modules/network"
  project_id  = var.project_id
  environment = var.environment
  region      = var.region
  subnet_cidr = var.subnet_cidr
}

# Dedicated service account and IAM bindings for cluster nodes
module "iam" {
  source      = "../../modules/iam"
  project_id  = var.project_id
  environment = var.environment
}

# VPC firewall rules — SSH and API restricted to admin_cidr, ingress open
module "firewall" {
  source       = "../../modules/firewall"
  project_id   = var.project_id
  environment  = var.environment
  network_name = module.network.network_name
  subnet_cidr  = module.network.subnet_cidr
  admin_cidr   = var.admin_cidr
}

# GCS bucket for CloudNativePG backups
module "gcs" {
  source                = "../../modules/gcs"
  project_id            = var.project_id
  environment           = var.environment
  region                = var.region
  service_account_email = module.iam.service_account_email
}

# Three cluster nodes — control plane + 2 workers
# Each gets a reserved static internal IP to satisfy k3s stability requirements
module "nodes" {
  for_each = {
    "node-01" = { role = "control" }
    "node-02" = { role = "worker" }
    "node-03" = { role = "worker" }
  }

  source                = "../../modules/node"
  project_id            = var.project_id
  name                  = "${var.environment}-${each.key}"
  role                  = each.value.role
  environment           = var.environment
  machine_type          = var.machine_type
  zone                  = var.zone
  region                = var.region
  subnetwork_self_link  = module.network.subnetwork_self_link
  service_account_email = module.iam.service_account_email
  ssh_public_key        = var.ssh_public_key
}

# Postgres credentials stored in Secret Manager — pulled by ESO at runtime
resource "google_secret_manager_secret" "pg_superuser_password" {
  secret_id = "${var.environment}-pg-superuser-password"
  project   = var.project_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "pg_superuser_password" {
  secret      = google_secret_manager_secret.pg_superuser_password.id
  secret_data = var.pg_superuser_password
}

resource "google_secret_manager_secret" "pg_app_password" {
  secret_id = "${var.environment}-pg-app-password"
  project   = var.project_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "pg_app_password" {
  secret      = google_secret_manager_secret.pg_app_password.id
  secret_data = var.pg_app_password
}

resource "google_secret_manager_secret" "pg_replication_password" {
  secret_id = "${var.environment}-pg-replication-password"
  project   = var.project_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "pg_replication_password" {
  secret      = google_secret_manager_secret.pg_replication_password.id
  secret_data = var.pg_replication_password
}
