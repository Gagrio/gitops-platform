# Module: node
# Provisions a single GCE VM with a reserved static internal IP.
# Called once per node via for_each in the environment. Static IPs are mandatory
# because k3s embeds node identity at bootstrap time and breaks if IPs change.

# Reserved static internal IP — mandatory for k3s stability; node identity breaks if the IP changes
resource "google_compute_address" "internal" {
  name         = "${var.name}-internal-ip"
  subnetwork   = var.subnetwork_self_link
  address_type = "INTERNAL"
  region       = var.region
  project      = var.project_id
}

# GCE VM running Ubuntu 24.04 LTS
resource "google_compute_instance" "node" {
  name         = var.name
  machine_type = var.machine_type
  zone         = var.zone
  project      = var.project_id

  boot_disk {
    initialize_params {
      # Ubuntu 24.04 LTS — current LTS, supported by k3s and all Ansible roles
      image = "ubuntu-os-cloud/ubuntu-2404-lts"
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
