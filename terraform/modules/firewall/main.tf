# Allow SSH from operator CIDR only — locked down, not world-open
resource "google_compute_firewall" "ssh" {
  name    = "${var.environment}-allow-ssh"
  network = var.network_name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.admin_cidr]
  target_tags   = [var.environment]
}

# Allow Kubernetes API server from operator CIDR only
resource "google_compute_firewall" "k8s_api" {
  name    = "${var.environment}-allow-k8s-api"
  network = var.network_name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }

  source_ranges = [var.admin_cidr]
  target_tags   = [var.environment]
}

# Allow HTTP and HTTPS for ingress traffic
resource "google_compute_firewall" "ingress" {
  name    = "${var.environment}-allow-ingress"
  network = var.network_name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [var.environment]
}

# Allow all intra-cluster traffic — nodes must communicate freely for k3s and CNI
resource "google_compute_firewall" "internal" {
  name    = "${var.environment}-allow-internal"
  network = var.network_name
  project = var.project_id

  allow {
    protocol = "all"
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = [var.environment]
}
