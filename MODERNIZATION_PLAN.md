# Astro — Test & Dependency Modernization Plan

**Date:** 2026-08-03
**Branch:** `claude/review-tests-dependencies-fq0n07`
**Toolchain used for analysis:** Go 1.24.7 (linux/amd64)

---

## Executive summary

**No unit test in this repo currently fails.** All 7 test packages pass on Go 1.24,
including under `-race`, and `go vet`, `gofmt`, and `golint` are all clean.

The real problem is that the project is pinned to a **~5-year-old dependency set**
(Go 1.15, Kubernetes client libraries v0.20.2 / k8s 1.20, released Jan 2021) and a
**CI pipeline that cannot run anymore** — nearly every external URL, base image,
and tool version it references is dead or removed upstream.

The good news: the upgrade path was prototyped end-to-end against the current
Kubernetes libraries and **it is nearly free**. Bringing the whole stack to
Kubernetes v0.34.1 / Go 1.24 requires exactly **two lines of Go source change**,
and shrinks the module graph from **314 modules to 134**.

---

## Part 1 — Current state (measured, not assumed)

### 1.1 Tests all pass today

| Check | Command | Result |
|---|---|---|
| Build | `go build ./...` | pass |
| Unit tests | `go test ./...` | pass (config, controller, handler, metrics) |
| Race detector | `go test -race -count=1 ./pkg/...` | pass |
| Vet | `go vet ./...` | clean |
| Format | `gofmt -l .` | clean |
| Lint | `golint -set_exit_status ./...` | clean |
| CI test command | `go test -v --bench --benchmem -coverprofile=... ./pkg/...` | pass, coverage 56.2% (handler) |

There are 7 test files covering 4 of the 8 packages. `pkg/datadog`, `pkg/kube`,
`pkg/mocks`, and `cmd` have no tests (0% coverage).

### 1.2 The one latent bug

There is a single genuine defect, and it is **currently invisible** only because
`go.mod` declares `go 1.15`. Go's `printf` vet check for non-constant format
strings activates at language version 1.24, so the moment the `go` directive is
bumped, `go test` fails to build:

```
pkg/config/config.go:300:13: non-constant format string in call to github.com/sirupsen/logrus.Debugf
```

```go
// pkg/config/config.go:300  — current
log.Debugf(fmt.Sprintf("Using default value %s for %s", defaultVal, key))
```

This is the "failing test" that a dependency update surfaces. The fix is one line
(plus dropping the now-unused `fmt` import), and it matches the style already used
on the two neighbouring lines (300/316/325).

### 1.3 CI is comprehensively broken

`.circleci/config.yml` is unrunnable today. This is independent of the Go code:

| Item | Pinned | Problem |
|---|---|---|
| Test/release image | `cimg/go:1.14` | Older than `go.mod`'s own `go 1.15` directive |
| Dockerfile base | `golang:1.14` | EOL; GOPATH-style layout |
| Linter | `go get -u golang.org/x/lint/golint` | `golint` is deprecated/frozen; bare `go get` for binaries was removed in Go 1.22 |
| Benchmark flag | `--bench --benchmem` | Malformed. `-bench` takes a value, so this parses as `-bench="--benchmem"` — a regex matching **no** benchmarks. Benchmarks have never run. |
| Coverage upload | `bash <(curl -s https://codecov.io/bash)` | Codecov's bash uploader was sunset; endpoint no longer serves a working script |
| Release | `curl -sL http://git.io/goreleaser \| bash` | `git.io` was shut down by GitHub in April 2022 — **hard failure** |
| E2E clusters | kind node images k8s **1.15.7 / 1.16.4 / 1.17.0** | All long EOL; ~9 minor versions behind the client libraries |
| Orb | `fairwinds/rok8s-scripts@11` | Unmaintained for this use |

`hack/kind/setup.sh` is equally stale: it requires **Helm 2 / Tiller** (dead),
calls `kind get kubeconfig-path` (removed in kind 0.6+), pins node image
`v1.13.10`, and `hack/kind/kind.yaml` uses API `kind.sigs.k8s.io/v1alpha3`
(current is `kind.x-k8s.io/v1alpha4`).

`e2e/pre.sh` pins `yq` **2.4.0** and uses `yq w -i` syntax, which was replaced
wholesale in yq v4.

**Also note:** CircleCI is the only place tests run, and this fork has no
CircleCI project — the sole GitHub Actions workflow is `stale.yml`. In practice
**nothing is testing this repository right now.**

### 1.4 Dependency staleness

Direct dependencies, current vs. latest:

| Module | Current | Latest | Note |
|---|---|---|---|
| `k8s.io/api` / `apimachinery` / `client-go` | v0.20.2 | v0.36.3 | 16 minor versions behind |
| `sigs.k8s.io/controller-runtime` | v0.8.1 | v0.24.1 | used for **one** function call |
| `github.com/prometheus/client_golang` | v1.9.0 | v1.24.1 | |
| `github.com/spf13/cobra` | v1.1.1 | v1.10.2 | |
| `github.com/sirupsen/logrus` | v1.7.0 | v1.9.4 | |
| `github.com/stretchr/testify` | v1.6.1 | v1.11.1 | |
| `golang.org/x/time` | 2020-06-30 | v0.15.0 | |
| `github.com/imdario/mergo` | v0.3.11 | v1.0.2 | **module renamed** → `dario.cat/mergo` |
| `github.com/golang/mock` | v1.4.4 | v1.6.0 | **archived by Google** → `go.uber.org/mock` |
| `github.com/ghodss/yaml` | v1.0.0 | — | unmaintained → `sigs.k8s.io/yaml` (already in tree) |
| `github.com/zorkian/go-datadog-api` | v2.30.0 | v2.30.0 | already latest; upstream archived |

### 1.5 Security exposure

`govulncheck` **could not be run** — this environment's network policy blocks
`vuln.go.dev` (403 on CONNECT). This gap must be closed by running it in CI or on
an unrestricted machine; the list below is from inspecting the module graph, not
from a vulnerability database, so treat it as indicative rather than complete.

The current tree pulls in several abandoned/known-risky modules, **all of which
disappear on upgrade** because client-go v0.26+ removed the in-tree cloud auth
plugins:

| Module in current tree | Status |
|---|---|
| `github.com/dgrijalva/jwt-go v3.2.0` | abandoned; superseded by `golang-jwt` |
| `github.com/form3tech-oss/jwt-go v3.2.2` | fork of the above |
| `github.com/Azure/go-autorest/autorest/adal v0.9.5` | **retracted** by upstream; whole family deprecated |
| `cloud.google.com/go v0.72.0` | 2020 |
| `github.com/gogo/protobuf v1.3.1` | pre-1.3.2 |
| `golang.org/x/crypto`, `x/net`, `x/text v0.3.4` | all Nov/Dec 2020 |

After upgrade: the jwt-go, Azure autorest, and cloud.google.com families are gone
entirely, and `x/crypto`→v0.36.0, `x/net`→v0.38.0, `x/text`→v0.23.0,
`gogo/protobuf`→v1.3.2.

---

## Part 2 — The plan

### Phase 1 — Fix the latent bug (do this first, standalone)

Independently valuable and reviewable in isolation.

1. `pkg/config/config.go:300` — replace `log.Debugf(fmt.Sprintf(...))` with
   `log.Debugf("Using default value %s for %s", defaultVal, key)`.
2. Remove the now-unused `"fmt"` import.

**Verify:** `go vet ./... && go test ./...`

### Phase 2 — Toolchain and Kubernetes libraries

This is the core of the work and is **fully validated** (see Part 3).

1. `go mod edit -go=1.24`
2. Upgrade the k8s stack:
   ```
   go get k8s.io/api@v0.34.1 k8s.io/apimachinery@v0.34.1 \
          k8s.io/client-go@v0.34.1 sigs.k8s.io/controller-runtime@v0.22.1
   go mod tidy
   ```
   Chosen deliberately over the very latest (v0.36.x): v0.34.1 pairs with a
   released `controller-runtime` and is a well-trodden combination. Moving to
   v0.36.x afterwards is a small follow-up.
3. `gofmt -w` any files whose import blocks shift.

**No Go source changes are required for this phase** beyond Phase 1 — verified by
building and testing the whole tree against v0.34.1.

Two API-compatibility notes worth recording, both confirmed non-breaking here:
- `SharedInformer.AddEventHandler` gained a `(registration, error)` return in
  client-go v0.26. `pkg/controller/controller.go:213` calls it as a bare
  statement, which stays legal. **Consider** capturing and checking the error as
  a follow-up quality improvement.
- The `workqueue.RateLimitingInterface` / `NewRateLimitingQueue` /
  `NewMaxOfRateLimiter` APIs used in `pkg/controller/controller.go` are
  *deprecated* in favour of the generic `Typed*` variants but still compile at
  v0.34.1. Migrating to `TypedRateLimitingInterface[config.Event]` would also
  remove the `evt.(config.Event)` type assertions in `next()` — a clean,
  self-contained follow-up, not a blocker.

### Phase 3 — Renamed / abandoned modules

Each is a mechanical import rewrite; all three were validated together.

| Change | Import rewrite |
|---|---|
| mergo v1 | `github.com/imdario/mergo` → `dario.cat/mergo` |
| Google mock → Uber mock | `github.com/golang/mock/gomock` → `go.uber.org/mock/gomock` |
| yaml | `github.com/ghodss/yaml` → `sigs.k8s.io/yaml` |

Notes:
- `sigs.k8s.io/yaml` is a maintained continuation of `ghodss/yaml` with the same
  API, and is **already** in the dependency tree via client-go — this removes a
  dependency rather than adding one.
- `pkg/mocks/datadog_mock.go` is a checked-in generated file; its import header
  changes with the rest. Regenerate with `mockgen` from `go.uber.org/mock` and
  keep the existing caveat noted in `pkg/datadog/test_helpers.go:3`.
- mergo v1 was specifically re-tested uncached because it drives config merging
  (`pkg/config`) — behaviour is unchanged.

### Phase 4 — Remaining direct dependencies

```
go get github.com/prometheus/client_golang@latest github.com/spf13/cobra@latest \
       github.com/sirupsen/logrus@latest github.com/stretchr/testify@latest \
       golang.org/x/time@latest
go mod tidy
```
Low risk; each is used through a small, stable surface.

### Phase 5 — Rebuild CI (largest effort, highest payoff)

Because nothing currently runs CI on this fork, the recommendation is to **add a
GitHub Actions workflow rather than repair CircleCI**.

1. **New `.github/workflows/ci.yml`**: `actions/setup-go` pinned to the `go.mod`
   version, then build / `go vet` / `gofmt -l` / `go test -race -coverprofile`.
2. **Replace `golint`** with `golangci-lint` (via `golangci/golangci-lint-action`)
   or `staticcheck`. `golint` is frozen and should not be reintroduced.
3. **Fix the benchmark flag**: use `-bench=.` (or drop it — there are no
   benchmarks in the tree today, so the flag is currently decorative).
4. **Replace the codecov bash uploader** with `codecov/codecov-action`.
5. **Add `govulncheck`** as a CI step. This closes the security gap that could not
   be checked in this environment.
6. **Update `Dockerfile`**: modern `golang:1.24` builder, module-aware layout with
   layer-cached `go mod download`, and pin the distroless base by tag/digest.
7. **Fix the release job**: `git.io/goreleaser` is dead — use
   `goreleaser/goreleaser-action`. Also modernize `.goreleaser.yml` (it lacks a
   `version:` key required by GoReleaser v2, and builds amd64 only).

### Phase 6 — E2E and local dev infrastructure

Effectively a rewrite; can trail the rest.

1. `hack/kind/kind.yaml` → `kind.x-k8s.io/v1alpha4`.
2. `hack/kind/setup.sh` → drop Helm 2/Tiller and `kind get kubeconfig-path`;
   use Helm 3 and `kind get kubeconfig`. Re-evaluate whether `reckoner` is still
   wanted.
3. E2E matrix → supported Kubernetes versions (roughly 1.31–1.34) instead of
   1.15/1.16/1.17.
4. `e2e/pre.sh` → yq v4 syntax (`yq -i '...' file`) or `kustomize edit set image`.

### Phase 7 — Optional / longer-horizon

- **`zorkian/go-datadog-api` is archived upstream.** It is at its latest version,
  so there is nothing to bump, but it is a long-term liability. Migrating to the
  official `github.com/DataDog/datadog-api-client-go/v2` (v2.62.0) is a
  significant rewrite of `pkg/datadog` and its mocks — deliberately **out of scope**
  for a dependency refresh, but it should be tracked as its own issue.
- **Raise test coverage.** `pkg/datadog`, `pkg/kube`, and `cmd` have none;
  `pkg/handler` sits at 56.2%.
- **Typed workqueue migration** (see Phase 2 note).
- **`.github/dependabot.yml`** is Terraform-managed and includes an `npm` entry
  for a `/docs` directory that does not exist in this repo. Worth cleaning up at
  the source of truth.

---

## Part 3 — Validation already performed

The full Phase 1–4 upgrade was prototyped in a scratch copy of the repository and
verified green. Final state of that prototype:

```
ok   github.com/fairwindsops/astro/pkg/config      0.335s
ok   github.com/fairwindsops/astro/pkg/controller  0.518s
ok   github.com/fairwindsops/astro/pkg/handler     0.019s
ok   github.com/fairwindsops/astro/pkg/metrics     0.005s
go vet ./...            → clean
gofmt -l .              → clean
golint -set_exit_status → exit 0
```

Resulting direct requirements:

```go
require (
	dario.cat/mergo v1.0.2
	github.com/prometheus/client_golang v1.22.0
	github.com/sirupsen/logrus v1.9.3
	github.com/spf13/cobra v1.9.1
	github.com/stretchr/testify v1.10.0
	github.com/zorkian/go-datadog-api v2.30.0+incompatible
	go.uber.org/mock v0.6.0
	golang.org/x/time v0.9.0
	k8s.io/api v0.34.1
	k8s.io/apimachinery v0.34.1
	k8s.io/client-go v0.34.1
	sigs.k8s.io/controller-runtime v0.22.1
	sigs.k8s.io/yaml v1.6.0
)
```

**Module graph: 314 → 134 modules.**

---

## Sequencing

| Phase | Scope | Risk | Suggested PR |
|---|---|---|---|
| 1 | Non-constant format string fix | none | PR 1 (standalone) |
| 2 | Go 1.24 + k8s v0.34.1 | low — validated | PR 2 |
| 3 | mergo / mock / yaml renames | low — validated | PR 2 or 3 |
| 4 | Remaining direct deps | low | PR 3 |
| 5 | CI rebuild + Dockerfile + release | medium — needs iteration against real CI | PR 4 |
| 6 | E2E / kind / Helm 3 | medium–high — effectively a rewrite | PR 5 |
| 7 | Datadog client, coverage, typed workqueue | high / ongoing | tracked issues |

Phases 1–4 are the dependency refresh proper and are ready to implement
immediately. **Phase 5 should not be deferred long** — until CI runs, every later
change is unverified in an environment other than a developer's machine.

## Open items requiring a decision

1. **`govulncheck` was never run** (network-blocked here). Run it before treating
   the security section as settled.
2. **Kubernetes target version** — plan plumbs for v0.34.1; confirm the oldest
   cluster version Astro must support, since that also sets the E2E matrix.
3. **CI platform** — this plan assumes migrating to GitHub Actions. If CircleCI is
   still the intended home, Phase 5 changes shape but not size.
