#!/usr/bin/env bash
# Generates an Ansible inventory file at /tmp/hosts.ini from GCP compute labels.
# Required env: GCP_PROJECT, ENVIRONMENT
set -euo pipefail

CONTROL=$(gcloud compute instances list \
  --project="$GCP_PROJECT" \
  --filter="labels.environment=$ENVIRONMENT AND labels.role=control" \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

WORKERS=$(gcloud compute instances list \
  --project="$GCP_PROJECT" \
  --filter="labels.environment=$ENVIRONMENT AND labels.role=worker" \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

cat > /tmp/hosts.ini << EOF
[control]
$CONTROL

[worker]
$WORKERS

[k3s_cluster:children]
control
worker
EOF

echo "Generated inventory:"
cat /tmp/hosts.ini
