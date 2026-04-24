output "bucket_name" {
  value = google_storage_bucket.backup.name
}

output "bucket_url" {
  value = google_storage_bucket.backup.url
}
