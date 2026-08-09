#!/usr/bin/env bash
# Delete the kind cluster and the project-local kubeconfig it wrote.

# shellcheck source=hack/dev/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_cmd kind
require_container_runtime

if ! cluster_exists; then
  log "kind cluster '$KIND_CLUSTER_NAME' does not exist, nothing to do"
  exit 0
fi

log "Deleting kind cluster '$KIND_CLUSTER_NAME'"
kind delete cluster --name "$KIND_CLUSTER_NAME"

# Only remove the kubeconfig when it is the throwaway one under .flox/cache --
# never touch a kubeconfig the developer pointed us at.
if [ -n "${KUBECONFIG:-}" ] && [ "$KUBECONFIG" = "$REPO_ROOT/.flox/cache/kubeconfig" ] && [ -f "$KUBECONFIG" ]; then
  rm -f "$KUBECONFIG"
  info "removed $KUBECONFIG"
fi
