output "service_account_email" {
  value = google_service_account.nodes.email
}

output "service_account_name" {
  value = google_service_account.nodes.name
}
