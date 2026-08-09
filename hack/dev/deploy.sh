#!/usr/bin/env bash
# Build astro, load the image into the kind cluster, and install it.
#
# The image is assembled from a binary cross-compiled with the host toolchain
# (see hack/dev/Dockerfile), which keeps the edit -> deploy loop at a few
# seconds instead of a full golang-base-image rebuild.

# shellcheck source=hack/dev/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_cmd go kind kubectl
require_container_runtime

cluster_exists || die "kind cluster '$KIND_CLUSTER_NAME' does not exist. Run hack/dev/cluster-up.sh first."

cd "$REPO_ROOT"

# kind nodes run linux on the host's architecture.
GOARCH_TARGET="${GOARCH_TARGET:-$(go env GOARCH)}"

BUILD_CTX=$(mktemp -d)
RENDER_DIR=$(mktemp -d)
cleanup() { rm -rf "$BUILD_CTX" "$RENDER_DIR"; }
trap cleanup EXIT

log "Building astro for linux/$GOARCH_TARGET"
CGO_ENABLED=0 GOOS=linux GOARCH="$GOARCH_TARGET" \
  go build -ldflags "-s -w" -o "$BUILD_CTX/astro" .

# conf.yml is a symlink to conf-example.yml; copy the target so the build
# context contains a real file regardless of how the runtime handles symlinks.
cp "$REPO_ROOT/conf-example.yml" "$BUILD_CTX/conf.yml"
cp "$REPO_ROOT/hack/dev/Dockerfile" "$BUILD_CTX/Dockerfile"

log "Building image $ASTRO_IMAGE with $CONTAINER_RUNTIME"
"$CONTAINER_RUNTIME" build -t "$ASTRO_IMAGE" "$BUILD_CTX"

log "Loading $ASTRO_IMAGE into kind cluster '$KIND_CLUSTER_NAME'"
kind load docker-image "$ASTRO_IMAGE" --name "$KIND_CLUSTER_NAME"

log "Applying manifests to namespace '$ASTRO_NAMESPACE'"
kubectl create namespace "$ASTRO_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Re-point the image at the locally built one and honour $ASTRO_NAMESPACE.
# Everything else in hack/manifests is applied verbatim, so this exercises the
# manifests the project actually ships.
for manifest in "$REPO_ROOT"/hack/manifests/*.yaml; do
  sed -e "s#image: quay.io/fairwinds/astro:.*#image: $ASTRO_IMAGE#" \
      -e "s#imagePullPolicy: .*#imagePullPolicy: IfNotPresent#" \
      -e "s#^\( *\)namespace: astro\$#\1namespace: $ASTRO_NAMESPACE#" \
      "$manifest" > "$RENDER_DIR/$(basename "$manifest")"
done

deployment_existed=false
if kubectl -n "$ASTRO_NAMESPACE" get deployment astro >/dev/null 2>&1; then
  deployment_existed=true
fi

kubectl apply -f "$RENDER_DIR/"

# The image tag does not change between builds, so an existing deployment needs
# an explicit restart to pick up the newly loaded image.
if [ "$deployment_existed" = true ]; then
  log "Restarting astro to pick up the new image"
  kubectl -n "$ASTRO_NAMESPACE" rollout restart deployment/astro
fi

log "Waiting for astro to become available"
kubectl -n "$ASTRO_NAMESPACE" rollout status deployment/astro --timeout=180s

kubectl -n "$ASTRO_NAMESPACE" get pods
info "logs: kubectl -n $ASTRO_NAMESPACE logs -l app.kubernetes.io/name=astro -f"
