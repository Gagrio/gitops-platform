# Reserved static internal IP — mandatory for k3s stability; node identity breaks if the IP changes
resource "google_compute_address" "internal" {
  name         = "${var.name}-internal-ip"
  subnetwork   = var.subnetwork_self_link
  address_type = "INTERNAL"
  region       = var.region
  project      = var.project_id
}

# GCE VM running Ubuntu 22.04 LTS
resource "google_compute_instance" "node" {
  name         = var.name
  machine_type = var.machine_type
  zone         = var.zone
  project      = var.project_id

  boot_disk {
    initialize_params {
      # Ubuntu 22.04 LTS — stable, well-supported by k3s and Ansible roles
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 50
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = var.subnetwork_self_link
    network_ip = google_compute_address.internal.address

    # Ephemeral external IP — used for SSH during provisioning only
    access_config {}
  }

  # SSH public key injected at instance creation; Ansible uses this to connect
  metadata = {
    ssh-keys = "${var.ssh_user}:${var.ssh_public_key}"
  }

  # Node SA with minimal permissions scoped at the project level via IAM module
  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  # Tags used by firewall rules to target specific instances
  tags = [var.environment, var.role]

  labels = {
    environment = var.environment
    role        = var.role
  }
}
