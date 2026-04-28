#!/usr/bin/env bash
# Outputs the external IP of the control plane node.
# Required env: GCP_PROJECT, ENVIRONMENT
set -euo pipefail

gcloud compute instances list \
  --project="$GCP_PROJECT" \
  --filter="labels.environment=$ENVIRONMENT AND labels.role=control" \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)"
