#!/usr/bin/env bash
# End-to-end check of astro running in the kind cluster.
#
#   1. astro's deployment becomes available
#   2. the /metrics endpoint serves the astro metrics
#   3. a workload annotated for the deployment ruleset makes astro reconcile a
#      monitor (in dry-run, so no Datadog account is needed)

# shellcheck source=hack/dev/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl curl

METRICS_LOCAL_PORT="${METRICS_LOCAL_PORT:-18080}"
LOG_WAIT_SECONDS="${LOG_WAIT_SECONDS:-90}"
DRY_RUN_LOG_LINE="Running as DryRun, skipping DataDog update"

kubectl -n "$ASTRO_NAMESPACE" get deployment astro >/dev/null 2>&1 \
  || die "astro is not installed in namespace '$ASTRO_NAMESPACE'. Run hack/dev/deploy.sh first."

log "1/3 Waiting for the astro deployment to be available"
kubectl -n "$ASTRO_NAMESPACE" wait deployment/astro \
  --for=condition=available --timeout=180s
info "available"

log "2/3 Checking the metrics endpoint"
kubectl -n "$ASTRO_NAMESPACE" port-forward deployment/astro \
  "$METRICS_LOCAL_PORT:8080" >/dev/null 2>&1 &
port_forward_pid=$!
cleanup_port_forward() {
  if kill -0 "$port_forward_pid" 2>/dev/null; then
    kill "$port_forward_pid" 2>/dev/null || true
    wait "$port_forward_pid" 2>/dev/null || true
  fi
}
trap cleanup_port_forward EXIT

metrics=""
for _ in $(seq 1 30); do
  if metrics=$(curl -sf "http://127.0.0.1:$METRICS_LOCAL_PORT/metrics" 2>/dev/null); then
    break
  fi
  sleep 1
done

[ -n "$metrics" ] || die "could not reach /metrics through the port-forward"
echo "$metrics" | grep -q '^astro_' \
  || die "/metrics responded but exposed no astro_* metrics"
info "$(echo "$metrics" | grep -c '^astro_') astro_* metric samples exposed"

cleanup_port_forward
trap - EXIT

log "3/3 Reconciling a monitor for an annotated workload"
# Note the timestamp first so the log check cannot pass on output from an
# earlier run of this script.
since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
kubectl apply -f "$REPO_ROOT/hack/dev/demo-workload.yaml"
kubectl -n "$ASTRO_DEMO_NAMESPACE" rollout status deployment/astro-demo-workload --timeout=120s

info "waiting up to ${LOG_WAIT_SECONDS}s for astro to process the deployment event"
found=false
for _ in $(seq 1 "$LOG_WAIT_SECONDS"); do
  if kubectl -n "$ASTRO_NAMESPACE" logs -l app.kubernetes.io/name=astro \
       --since-time="$since" --tail=-1 2>/dev/null | grep -qF "$DRY_RUN_LOG_LINE"; then
    found=true
    break
  fi
  sleep 1
done

if [ "$found" != true ]; then
  echo
  echo "--- astro logs ---"
  kubectl -n "$ASTRO_NAMESPACE" logs -l app.kubernetes.io/name=astro --tail=100 || true
  die "astro never logged '$DRY_RUN_LOG_LINE'; it did not reconcile a monitor for the demo workload"
fi
info "astro reconciled a monitor in dry-run mode"

log "Smoke test passed"
info "tear down with hack/dev/cluster-down.sh"
