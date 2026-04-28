#!/usr/bin/env bash
# Outputs external IPs of cluster nodes, space-separated.
# Usage: get-node-ips.sh [role]
#   role — optional GCP node label value (e.g. "control", "worker")
#           omit to return all nodes in the environment
# Required env: GCP_PROJECT, ENVIRONMENT
set -euo pipefail

FILTER="labels.environment=$ENVIRONMENT"
[[ -n "${1:-}" ]] && FILTER+=" AND labels.role=$1"

gcloud compute instances list \
  --project="$GCP_PROJECT" \
  --filter="$FILTER" \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)" \
  | tr '\n' ' ' | xargs
