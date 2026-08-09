#!/usr/bin/env bash
# Create (or reuse) the kind cluster astro is developed against.

# shellcheck source=hack/dev/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_cmd kind kubectl
require_container_runtime

if cluster_exists; then
  log "kind cluster '$KIND_CLUSTER_NAME' already exists"
else
  log "Creating kind cluster '$KIND_CLUSTER_NAME' ($KIND_NODE_IMAGE) via $CONTAINER_RUNTIME"
  kind create cluster \
    --name "$KIND_CLUSTER_NAME" \
    --image "$KIND_NODE_IMAGE" \
    --config "$REPO_ROOT/hack/dev/kind.yaml" \
    --wait 120s
fi

log "Writing kubeconfig"
kind export kubeconfig --name "$KIND_CLUSTER_NAME"
info "KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}"

log "Waiting for nodes to be ready"
kubectl wait --for=condition=Ready nodes --all --timeout=180s

kubectl get nodes
