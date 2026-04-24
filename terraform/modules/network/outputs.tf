output "network_name" {
  value = google_compute_network.main.name
}

output "network_self_link" {
  value = google_compute_network.main.self_link
}

output "subnetwork_name" {
  value = google_compute_subnetwork.main.name
}

output "subnetwork_self_link" {
  value = google_compute_subnetwork.main.self_link
}

output "subnet_cidr" {
  value = google_compute_subnetwork.main.ip_cidr_range
}
