#!/usr/bin/env bash
# Build the astro binary for the host into bin/astro.

# shellcheck source=hack/dev/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_cmd go

cd "$REPO_ROOT"

VERSION="${VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"

log "Building astro ($VERSION) for $(go env GOOS)/$(go env GOARCH)"
mkdir -p bin
go build -ldflags "-s -w" -o bin/astro .

info "bin/astro"
