output "ci_service_account_email" {
  value       = google_service_account.ci_deployer.email
  description = "Email of the CI service account — also stored in GitHub secret GCP_SERVICE_ACCOUNT"
}

output "workload_identity_provider" {
  value       = google_iam_workload_identity_pool_provider.github.name
  description = "WIF provider resource name — also stored in GitHub secret GCP_WORKLOAD_IDENTITY_PROVIDER"
}
