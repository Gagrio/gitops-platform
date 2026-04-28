#!/usr/bin/env bash
# Functional health assertions — runs on every deploy, always fast.
# Verifies nodes, Postgres pods, and application reachability.
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
  echo "--- Ingress resources ---"
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
echo "  Waiting for pg-1, pg-2, pg-3 to be Ready..."
$K wait pod/pg-1 pod/pg-2 pod/pg-3 -n postgres --for=condition=Ready --timeout=60s
echo "✓ All 3 Postgres instances Ready"

# ── [3/4] Adminer pod ────────────────────────────────────────────────────────
echo ""
echo "=== [3/4] Adminer pod ==="
$K get pods -n demo-app -o wide
echo "  Waiting for Adminer pod to be Ready..."
$K wait pods -n demo-app -l app=adminer --for=condition=Ready --timeout=60s
echo "✓ Adminer pod Ready"

# ── [4/4] Adminer HTTP endpoint ───────────────────────────────────────────────
echo ""
echo "=== [4/4] Adminer HTTP endpoint ==="
INGRESS_NODE=$($K get pod -n ingress-nginx \
  -l app.kubernetes.io/name=ingress-nginx \
  -o jsonpath='{.items[0].spec.nodeName}')
INGRESS_IP=$($K get node "$INGRESS_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="ExternalIP")].address}')
echo "  Sending GET http://${INGRESS_IP}/adminer ..."
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -L --max-time 10 \
  http://"${INGRESS_IP}"/adminer)
if [[ "$STATUS" != "200" ]]; then
  echo "  FAIL: Adminer returned HTTP ${STATUS} — expected 200"
  exit 1
fi
echo "✓ Adminer reachable — HTTP ${STATUS}"

echo ""
echo "✅ All health checks passed!"

# ── Access summary ────────────────────────────────────────────────────────────
ENV="${ENVIRONMENT:-dev}"
echo ""
echo "=================================================="
echo "  PLATFORM ACCESS"
echo "=================================================="
echo ""
echo "  Adminer (Database UI)"
echo "  URL:      http://${INGRESS_IP}/adminer"
echo "  System:   PostgreSQL"
echo "  Server:   pg-rw.postgres.svc.cluster.local"
echo "  Username: app"
echo "  Database: app"
echo "  Password: gcloud secrets versions access latest --secret=${ENV}-pg-app-password"
echo ""
echo "  Grafana (Monitoring)"
echo "  URL:      http://${INGRESS_IP}/grafana"
echo "  Username: admin"
echo "  Password: gcloud secrets versions access latest --secret=${ENV}-grafana-admin-password"
echo "=================================================="
