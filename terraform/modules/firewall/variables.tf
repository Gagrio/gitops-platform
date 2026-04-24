variable "project_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "network_name" {
  type = string
}

variable "subnet_cidr" {
  type = string
}

variable "admin_cidr" {
  type        = string
  description = "CIDR allowed to reach SSH and the Kubernetes API. Set to your operator IP, e.g. 203.0.113.10/32"
}
