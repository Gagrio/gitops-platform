output "subnet_cidr" {
  value = module.network.subnet_cidr
}

# Node IPs consumed by Ansible to build the inventory
output "node_internal_ips" {
  value = { for k, v in module.nodes : k => v.internal_ip }
}

output "node_external_ips" {
  value = { for k, v in module.nodes : k => v.external_ip }
}

output "backup_bucket_name" {
  value = module.gcs.bucket_name
}

output "service_account_email" {
  value = module.iam.service_account_email
}
