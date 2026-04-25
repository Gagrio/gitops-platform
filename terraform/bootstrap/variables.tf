variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub personal access token with repo scope — used to create GitHub Actions secrets"
}

variable "github_owner" {
  type        = string
  description = "GitHub username or organisation that owns the repository"
}

variable "github_repo" {
  type    = string
  default = "enclaive-platform-challenge"
}

variable "tf_state_bucket" {
  type        = string
  description = "Name of the GCS bucket created manually for Terraform state"
}

variable "admin_cidr" {
  type        = string
  description = "Your public IP in CIDR notation (e.g. 203.0.113.10/32) — restricts SSH and k8s API access"
}

variable "subnet_cidr" {
  type        = string
  default     = "10.0.0.0/24"
  description = "Subnet CIDR for the cluster nodes — must match the value in environments/dev/variables.tf"
}

variable "ssh_public_key" {
  type        = string
  description = "Contents of the SSH public key file (~/.ssh/enclaive-ci.pub) — injected into GCE nodes"
}
