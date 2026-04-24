variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "zone" {
  type    = string
  default = "europe-west1-b"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.0.0/24"
}

variable "admin_cidr" {
  type        = string
  description = "Your operator IP in CIDR notation, e.g. 203.0.113.10/32. Restricts SSH and k8s API access."
}

variable "ssh_public_key" {
  type        = string
  sensitive   = true
  description = "SSH public key injected into all nodes for Ansible access"
}

variable "pg_superuser_password" {
  type      = string
  sensitive = true
}

variable "pg_app_password" {
  type      = string
  sensitive = true
}

variable "pg_replication_password" {
  type      = string
  sensitive = true
}
