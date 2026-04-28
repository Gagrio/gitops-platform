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

# ── [1/6] Flux kustomizations appear ─────────────────────────────────────────
echo ""
echo "=== [1/6] Waiting for Flux kustomizations to appear ==="
timeout 120 bash -c \
  'until sudo k3s kubectl get kustomization common -n flux-system &>/dev/null; \
   do echo "  … Flux not yet started, retrying in 5s"; sleep 5; done'
echo "  Current state:"
$K get kustomization -A

# ── [2/6] common ─────────────────────────────────────────────────────────────
echo ""
echo "=== [2/6] common kustomization (ingress-nginx, ESO, CNPG operator) ==="
$K wait kustomization/common -n flux-system --for=condition=Ready --timeout=600s
echo "  HelmReleases:"
$K get helmrelease -A
echo "✓ common Ready"

# ── [3/6] eso-config ─────────────────────────────────────────────────────────
echo ""
echo "=== [3/6] eso-config kustomization (ClusterSecretStore + ExternalSecrets) ==="
$K wait kustomization/eso-config -n flux-system --for=condition=Ready --timeout=120s
echo "  Syncing secrets from GCP Secret Manager..."
for secret in grafana-admin-password pg-superuser-password pg-app-password pg-replication-password; do
  ns=$( [[ "$secret" == "grafana-admin-password" ]] && echo monitoring || echo postgres )
  $K wait externalsecret/"$secret" -n "$ns" --for=condition=Ready --timeout=60s
  echo "    ✓ $secret → namespace/$ns"
done

# ── [4/6] postgres kustomization ─────────────────────────────────────────────
echo ""
echo "=== [4/6] postgres kustomization (Cluster CR, backup schedule, network policies) ==="
$K wait kustomization/postgres -n flux-system --for=condition=Ready --timeout=600s
echo "✓ postgres kustomization Ready"

# ── [5/6] demo-app kustomization ─────────────────────────────────────────────
echo ""
echo "=== [5/6] demo-app kustomization (Adminer) ==="
$K wait kustomization/demo-app -n flux-system --for=condition=Ready --timeout=300s
echo "✓ demo-app kustomization Ready"

# ── [6/6] Postgres cluster bootstrap ─────────────────────────────────────────
echo ""
echo "=== [6/6] Postgres cluster (3-instance HA, streaming replication) ==="
echo "  Polling every 30s — takes 5-15 min on first deploy, seconds on subsequent ones..."
DEADLINE=$((SECONDS + 900))
while true; do
  PHASE=$($K get cluster pg -n postgres \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
  READY=$($K get cluster pg -n postgres \
    -o jsonpath='{.status.readyInstances}' 2>/dev/null || echo "?")
  TOTAL=$($K get cluster pg -n postgres \
    -o jsonpath='{.status.instances}' 2>/dev/null || echo "?")
  REMAINING=$((DEADLINE - SECONDS))
  echo "  $(date -u +%H:%M:%SZ)  phase=\"${PHASE}\"  instances=${READY}/${TOTAL} ready  (${REMAINING}s remaining)"
  if $K wait cluster/pg -n postgres --for=condition=Ready --timeout=5s &>/dev/null; then
    PRIMARY=$($K get cluster pg -n postgres \
      -o jsonpath='{.status.targetPrimary}' 2>/dev/null)
    echo "✓ Cluster Ready — primary: ${PRIMARY}"
    break
  fi
  [[ $REMAINING -le 5 ]] && { echo "TIMEOUT: cluster/pg did not become Ready"; exit 1; }
  sleep 30
done

echo ""
echo "✅ Convergence complete — all Flux kustomizations reconciled, Postgres cluster Ready"
