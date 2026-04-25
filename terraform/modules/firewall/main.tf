# Module: firewall
# VPC firewall rules for the cluster. SSH and the Kubernetes API are restricted
# to the operator's CIDR. HTTP/HTTPS is open. Intra-cluster traffic is unrestricted
# within the subnet so k3s and Flannel CNI can operate freely.

# Allow SSH from anywhere — GitHub Actions runners have dynamic IPs so we cannot restrict
# by source CIDR. Key-based auth (enforced by the security Ansible role) and fail2ban
# are the real protection here. For production, replace this with GCP Cloud IAP tunneling.
resource "google_compute_firewall" "ssh" {
  name    = "${var.environment}-allow-ssh"
  network = var.network_name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [var.environment]
}

# Allow Kubernetes API server from operator CIDR only — CI does not need direct API access
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
