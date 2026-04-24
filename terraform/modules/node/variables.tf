variable "project_id" {
  type = string
}

variable "name" {
  type = string
}

variable "role" {
  type        = string
  description = "Node role label: control or worker"
}

variable "environment" {
  type = string
}

variable "machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "zone" {
  type = string
}

variable "region" {
  type = string
}

variable "subnetwork_self_link" {
  type = string
}

variable "service_account_email" {
  type = string
}

variable "ssh_user" {
  type    = string
  default = "ubuntu"
}

variable "ssh_public_key" {
  type      = string
  sensitive = true
}
