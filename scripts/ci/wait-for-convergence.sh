#!/usr/bin/env bash
# Waits for all Flux kustomizations and the Postgres cluster to converge.
# Runs remotely on the control plane: ssh ubuntu@<cp-ip> bash < scripts/ci/wait-for-convergence.sh
# Meaningful on first deploy; passes in seconds on subsequent ones (everything already Ready).
set -e

K="sudo k3s kubectl"

dump_diagnostics() {
  echo ""
  echo "===== DIAGNOSTICS ====="
  echo "--- Flux kustomizations ---"
  sudo k3s kubectl get kustomization -A 2>/dev/null || true
  echo "--- HelmReleases ---"
  sudo k3s kubectl get helmrelease -A 2>/dev/null || true
  echo "--- ExternalSecrets ---"
  sudo k3s kubectl get externalsecret -A 2>/dev/null || true
  echo "--- Postgres cluster ---"
  sudo k3s kubectl get cluster -n postgres 2>/dev/null || true
  echo "--- Pods (all namespaces) ---"
  sudo k3s kubectl get pods -A 2>/dev/null || true
  echo "--- Recent kustomize-controller logs ---"
  sudo k3s kubectl logs -n flux-system \
    deployment/kustomize-controller --tail=40 2>/dev/null || true
  echo "===== END DIAGNOSTICS ====="
}
trap 'EC=$?; [[ $EC -ne 0 ]] && dump_diagnostics' EXIT

# Polls a Flux kustomization, printing its status message every 15s.
# Flux sets the message to what it's actually doing (installing a HelmRelease,
# waiting on a dependency, applied revision, etc.) so this gives real progress.
wait_kustomization() {
  local name=$1
  local timeout=$2
  local DEADLINE=$((SECONDS + timeout))
  while true; do
    local MSG REMAINING
    MSG=$($K get kustomization/"$name" -n flux-system \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null \
      || echo "not found yet")
    REMAINING=$((DEADLINE - SECONDS))
    echo "  $(date -u +%H:%M:%SZ)  $name: ${MSG}  (${REMAINING}s remaining)"
    if $K wait kustomization/"$name" -n flux-system \
        --for=condition=Ready --timeout=5s &>/dev/null; then
      echo "✓ $name Ready"
      return 0
    fi
    [[ $REMAINING -le 5 ]] && { echo "TIMEOUT: $name did not become Ready"; return 1; }
    sleep 15
  done
}

# ── [1/6] Flux kustomizations appear ─────────────────────────────────────────
echo ""
echo "=== [1/6] Waiting for Flux to start ==="
echo "  Retrying every 5s until the kustomization API is available..."
timeout 120 bash -c \
  'until sudo k3s kubectl get kustomization common -n flux-system &>/dev/null; \
   do echo "  $(date -u +%H:%M:%SZ)  Flux controllers not yet running"; sleep 5; done'
echo "  Kustomizations registered:"
$K get kustomization -A

# ── [2/6] common ─────────────────────────────────────────────────────────────
echo ""
echo "=== [2/6] common (installs ingress-nginx, ESO, and CNPG operator via HelmRelease) ==="
echo "  HelmReleases can take several minutes to pull and install on first deploy."
wait_kustomization common 600
echo "  HelmReleases:"
$K get helmrelease -A

# ── [3/6] eso-config ─────────────────────────────────────────────────────────
echo ""
echo "=== [3/6] eso-config (ClusterSecretStore + ExternalSecrets → GCP Secret Manager) ==="
wait_kustomization eso-config 120
echo "  Waiting for each ExternalSecret to sync from GCP Secret Manager..."
for secret in grafana-admin-password pg-superuser-password pg-app-password pg-replication-password; do
  ns=$( [[ "$secret" == "grafana-admin-password" ]] && echo monitoring || echo postgres )
  $K wait externalsecret/"$secret" -n "$ns" --for=condition=Ready --timeout=60s
  echo "    ✓ $secret synced to namespace/$ns"
done

# ── [4/6] postgres kustomization ─────────────────────────────────────────────
echo ""
echo "=== [4/6] postgres (Cluster CR, scheduled backup, network policies) ==="
wait_kustomization postgres 600

# ── [5/6] demo-app kustomization ─────────────────────────────────────────────
echo ""
echo "=== [5/6] demo-app (Adminer deployment, service, ingress) ==="
wait_kustomization demo-app 300

# ── [6/6] Postgres cluster bootstrap ─────────────────────────────────────────
echo ""
echo "=== [6/6] Postgres cluster bootstrapping ==="
echo "  CNPG provisions 3 instances with streaming replication and WAL archiving to GCS."
echo "  First deploy takes 5-15 min. Subsequent deploys pass in seconds."
DEADLINE=$((SECONDS + 900))
while true; do
  PHASE=$($K get cluster pg -n postgres \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "not yet visible")
  READY=$($K get cluster pg -n postgres \
    -o jsonpath='{.status.readyInstances}' 2>/dev/null || echo "0")
  TOTAL=$($K get cluster pg -n postgres \
    -o jsonpath='{.status.instances}' 2>/dev/null || echo "3")
  REMAINING=$((DEADLINE - SECONDS))
  echo "  $(date -u +%H:%M:%SZ)  ${PHASE}  —  ${READY}/${TOTAL} instances ready  (${REMAINING}s remaining)"
  if $K wait cluster/pg -n postgres --for=condition=Ready --timeout=5s &>/dev/null; then
    PRIMARY=$($K get cluster pg -n postgres \
      -o jsonpath='{.status.targetPrimary}' 2>/dev/null)
    echo "✓ Postgres cluster Ready — primary: ${PRIMARY}"
    break
  fi
  [[ $REMAINING -le 5 ]] && { echo "TIMEOUT: cluster/pg did not become Ready"; exit 1; }
  sleep 30
done

echo ""
echo "✅ Convergence complete"
