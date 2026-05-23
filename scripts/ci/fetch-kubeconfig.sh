#!/usr/bin/env bash
# Fetches kubeconfig from the control plane and patches the server address to the external IP.
# Required env: GCP_PROJECT, ENVIRONMENT
set -euo pipefail

CP_IP=$(gcloud compute instances list \
  --project="$GCP_PROJECT" \
  --filter="labels.environment=$ENVIRONMENT AND labels.role=control" \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

KUBECONFIG_PATH="/tmp/kubeconfig-gitops-${ENVIRONMENT}"

scp -o StrictHostKeyChecking=no -i ~/.ssh/gitops-ci \
  ubuntu@"${CP_IP}":/etc/rancher/k3s/k3s.yaml \
  "$KUBECONFIG_PATH"

sed -i "s|https://127.0.0.1:6443|https://${CP_IP}:6443|" "$KUBECONFIG_PATH"

echo "Kubeconfig saved to $KUBECONFIG_PATH (server: https://${CP_IP}:6443)"
