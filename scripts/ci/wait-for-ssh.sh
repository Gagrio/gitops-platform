#!/usr/bin/env bash
# Polls SSH availability on all GCE nodes for the given environment.
# Required env: GCP_PROJECT, ENVIRONMENT
set -euo pipefail

for ip in $(gcloud compute instances list \
  --project="$GCP_PROJECT" \
  --filter="labels.environment=$ENVIRONMENT" \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)"); do
  echo "Waiting for SSH on $ip..."
  timeout 120 bash -c \
    "until ssh -o StrictHostKeyChecking=no -i ~/.ssh/enclaive-ci ubuntu@$ip 'echo ok' 2>/dev/null; \
     do sleep 5; done"
  echo "  ✓ $ip"
done
