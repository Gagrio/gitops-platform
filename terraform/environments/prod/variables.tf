variable "project_id" {
  type = string
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
  default = "prod"
}

# Larger machine type for production workloads
variable "machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "subnet_cidr" {
  type    = string
  default = "10.1.0.0/24"
}

variable "admin_cidr" {
  type = string
}

variable "ssh_public_key" {
  type      = string
  sensitive = true
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
