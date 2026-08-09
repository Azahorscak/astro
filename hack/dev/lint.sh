#!/usr/bin/env bash
# Formatting, vet and lint checks.
#
# This replaces the CircleCI `golint` step: golint has been frozen and
# deprecated upstream, and `go get`-ing a binary stopped working in Go 1.22.
# golangci-lint runs the same checks (and more) and comes from the Flox
# environment, so nothing needs installing at run time.

# shellcheck source=hack/dev/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_cmd go gofmt golangci-lint

cd "$REPO_ROOT"

log "gofmt"
unformatted=$(gofmt -l .)
if [ -n "$unformatted" ]; then
  echo "$unformatted"
  die "the files above are not gofmt-clean; run 'gofmt -w .'"
fi
info "clean"

log "go vet"
go vet ./...
info "clean"

log "golangci-lint"
golangci-lint run ./...
info "clean"
