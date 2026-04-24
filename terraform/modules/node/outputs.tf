output "internal_ip" {
  value = google_compute_address.internal.address
}

output "external_ip" {
  value = google_compute_instance.node.network_interface[0].access_config[0].nat_ip
}

output "name" {
  value = google_compute_instance.node.name
}
