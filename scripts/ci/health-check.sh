#!/usr/bin/env bash
# Fast functional health assertions — meaningful on both fresh and subsequent deploys.
# Runs remotely on the control plane: ssh ubuntu@<cp-ip> bash < scripts/ci/health-check.sh
set -e

K="sudo k3s kubectl"

dump_diagnostics() {
  echo ""
  echo "===== DIAGNOSTICS ====="
  echo "--- Pods (all namespaces) ---"
  sudo k3s kubectl get pods -A 2>/dev/null || true
  echo "--- Postgres cluster ---"
  sudo k3s kubectl get cluster -n postgres 2>/dev/null || true
  echo "--- Ingress ---"
  sudo k3s kubectl get ingress -A 2>/dev/null || true
  echo "===== END DIAGNOSTICS ====="
}
trap 'EC=$?; [[ $EC -ne 0 ]] && dump_diagnostics' EXIT

# ── [1/4] Nodes ───────────────────────────────────────────────────────────────
echo ""
echo "=== [1/4] Nodes ==="
$K get nodes -o wide
$K wait node --all --for=condition=Ready --timeout=60s
echo "✓ All nodes Ready"

# ── [2/4] Postgres pods ───────────────────────────────────────────────────────
echo ""
echo "=== [2/4] Postgres pods ==="
$K get pods -n postgres -o wide
$K wait pod/pg-1 pod/pg-2 pod/pg-3 -n postgres --for=condition=Ready --timeout=60s
echo "✓ pg-1, pg-2, pg-3 Ready"

# ── [3/4] Adminer pod ────────────────────────────────────────────────────────
echo ""
echo "=== [3/4] Adminer pod ==="
$K wait pods -n demo-app -l app=adminer --for=condition=Ready --timeout=60s
echo "✓ Adminer pod Ready"

# ── [4/4] Adminer HTTP endpoint ───────────────────────────────────────────────
echo ""
echo "=== [4/4] Adminer HTTP endpoint ==="
INGRESS_IP=$($K get pod -n ingress-nginx \
  -l app.kubernetes.io/name=ingress-nginx \
  -o jsonpath='{.items[0].status.hostIP}')
echo "  Ingress node IP: ${INGRESS_IP}"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -L --max-time 10 \
  http://"${INGRESS_IP}"/adminer)
if [[ "$STATUS" != "200" ]]; then
  echo "  Adminer returned HTTP ${STATUS} — expected 200"
  exit 1
fi
echo "✓ Adminer reachable at http://${INGRESS_IP}/adminer — HTTP ${STATUS}"

echo ""
echo "✅ All health checks passed!"
