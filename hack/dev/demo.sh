#!/usr/bin/env bash
# One shot: create the kind cluster, install astro on it, verify it works.

# shellcheck source=hack/dev/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

"$REPO_ROOT/hack/dev/cluster-up.sh"
"$REPO_ROOT/hack/dev/deploy.sh"
"$REPO_ROOT/hack/dev/smoke-test.sh"
