# Custom VPC — auto_create_subnetworks disabled so we control the subnet layout
resource "google_compute_network" "main" {
  name                    = "${var.environment}-vpc"
  auto_create_subnetworks = false
  project                 = var.project_id
}

# Single regional subnet for all cluster nodes
resource "google_compute_subnetwork" "main" {
  name          = "${var.environment}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.main.self_link
  project       = var.project_id
}
