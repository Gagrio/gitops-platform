variable "project_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "service_account_email" {
  type = string
}

variable "retention_days" {
  type        = number
  default     = 30
  description = "Days after which backup objects are automatically deleted"
}
