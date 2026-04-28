#!/usr/bin/env bash
# Outputs the external IPs of all nodes in the environment, space-separated.
# Required env: GCP_PROJECT, ENVIRONMENT
set -euo pipefail

gcloud compute instances list \
  --project="$GCP_PROJECT" \
  --filter="labels.environment=$ENVIRONMENT" \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)" \
  | tr '\n' ' ' | xargs
