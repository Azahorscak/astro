#!/usr/bin/env bash
# Shared helpers for the hack/dev scripts. Sourced, not executed.
#
# Every setting here can be overridden from the environment; the Flox manifest
# supplies the defaults for an activated environment, and the fallbacks below
# keep the scripts usable without Flox.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
export REPO_ROOT

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-astro-dev}"
KIND_NODE_IMAGE="${KIND_NODE_IMAGE:-kindest/node:v1.34.0}"
ASTRO_IMAGE="${ASTRO_IMAGE:-astro:dev}"
ASTRO_NAMESPACE="${ASTRO_NAMESPACE:-astro}"
# Namespace of the sample workload; must match hack/dev/demo-workload.yaml.
ASTRO_DEMO_NAMESPACE="astro-demo"
export KIND_CLUSTER_NAME KIND_NODE_IMAGE ASTRO_IMAGE ASTRO_NAMESPACE ASTRO_DEMO_NAMESPACE

# Outside a Flox activation, keep the demo cluster out of ~/.kube/config unless
# the caller has explicitly opted in to their own kubeconfig.
if [ "${ASTRO_DEV_SYSTEM_KUBECONFIG:-0}" != "1" ] && [ -z "${KUBECONFIG:-}" ]; then
  KUBECONFIG="$REPO_ROOT/.flox/cache/kubeconfig"
  mkdir -p "$(dirname "$KUBECONFIG")"
  export KUBECONFIG
fi

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' is not installed. Run 'flox activate' in $REPO_ROOT to get it."
  done
}

# Resolves the container runtime kind will use and exports the matching
# KIND_EXPERIMENTAL_PROVIDER. Sets CONTAINER_RUNTIME to docker or podman.
require_container_runtime() {
  if [ -n "${CONTAINER_RUNTIME:-}" ]; then
    return 0
  fi

  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    CONTAINER_RUNTIME="docker"
  elif command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
    CONTAINER_RUNTIME="podman"
    export KIND_EXPERIMENTAL_PROVIDER="podman"
  else
    die "no running docker or podman daemon found.

kind needs a container runtime, and a runtime daemon is the one thing Flox
cannot provide. Install and start one of:
  - Docker Desktop, Colima, OrbStack, or the Docker Engine package
  - podman (then 'podman machine start' on macOS)

Everything else -- building, unit tests, lint -- works without it."
  fi
  export CONTAINER_RUNTIME
}

cluster_exists() {
  kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER_NAME"
}
