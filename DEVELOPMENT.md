# Developing astro

Development is done inside a [Flox](https://flox.dev) environment. It pins the
Go toolchain, the linters, and `kubectl` + `kind`, so a clone plus
`flox activate` is everything you need to build astro, run its tests, and watch
it reconcile monitors against a throwaway Kubernetes cluster.

## Prerequisites

| | |
|:--|:--|
| [Flox](https://flox.dev/docs/install-flox/) | provides every tool listed below |
| A container runtime | **the one thing Flox cannot provide.** Docker Desktop, OrbStack, Colima, Docker Engine, or podman. Needed only by `kind`. |

Flox itself supports Linux and macOS on both x86_64 and aarch64; the
environment declares all four.

## Getting started

```bash
git clone https://github.com/fairwindsops/astro && cd astro
flox activate
```

The first activation resolves the package set and writes
`.flox/env/manifest.lock`. Commit that lockfile — it is what makes the
environment byte-for-byte reproducible for the next person.

Activation prints the tool versions it found, warns if no container runtime is
running, and lists the commands below.

## What you get

| Package | Used for |
|:--|:--|
| `go` (>= 1.25, as required by `go.mod`) | building and testing |
| `gopls`, `gotools`, `delve` | editor integration, `goimports`, `dlv` |
| `golangci-lint` | linting — replaces the deprecated `golint` |
| `mockgen` | regenerating `pkg/mocks` (the project uses `go.uber.org/mock`) |
| `kubectl`, `kind`, `kubernetes-helm` | the demo cluster |
| `jq`, `yq`, `curl`, `git` | used by the `hack/` and `e2e/` scripts |

Activation also:

* puts `go install` output in `.flox/cache/gobin` instead of `~/go/bin`, and
  adds it to `PATH`;
* points `KUBECONFIG` at `.flox/cache/kubeconfig` so the demo cluster never
  touches `~/.kube/config`. Set `ASTRO_DEV_SYSTEM_KUBECONFIG=1` before
  activating if you would rather keep your usual kubeconfig;
* exports `DRY_RUN=true`, so a locally run `./bin/astro` never writes to
  Datadog. (astro also forces dry-run on its own whenever `DD_API_KEY` /
  `DD_APP_KEY` are unset.)

## Everyday commands

Each alias is a thin wrapper around a script in `hack/dev/`; the scripts work
outside Flox too, as long as the tools are on `PATH`.

| Command | Script | Does |
|:--|:--|:--|
| `astro-build` | `hack/dev/build.sh` | builds `bin/astro` for your host |
| `astro-test` | — | `go test ./...` |
| `astro-lint` | `hack/dev/lint.sh` | `gofmt`, `go vet`, `golangci-lint` |
| `astro-cluster-up` | `hack/dev/cluster-up.sh` | creates the `astro-dev` kind cluster |
| `astro-deploy` | `hack/dev/deploy.sh` | builds an image, loads it into kind, applies `hack/manifests/` |
| `astro-smoke` | `hack/dev/smoke-test.sh` | verifies astro is running and reconciling |
| `astro-demo` | `hack/dev/demo.sh` | all three of the above, in order |
| `astro-cluster-down` | `hack/dev/cluster-down.sh` | deletes the cluster |

## Running against a demo cluster

```bash
flox activate
astro-demo
```

`astro-demo` will:

1. **Create a kind cluster** (`astro-dev`, one control plane + one worker) from
   `hack/dev/kind.yaml`, on a node image matched to the Kubernetes client
   libraries in `go.mod`.
2. **Build and install astro.** The binary is cross-compiled with the host
   toolchain and copied into a runtime-only image
   (`hack/dev/Dockerfile`), so a redeploy takes seconds rather than pulling a
   golang base image. The image is loaded straight into the kind nodes, and
   `hack/manifests/` is applied with only the image reference rewritten — so
   you are exercising the manifests the project actually ships.
3. **Smoke-test it**, by checking that the deployment goes available, that
   `/metrics` serves `astro_*` samples, and that astro reconciles a monitor for
   `hack/dev/demo-workload.yaml` — a deployment annotated `astro/owner: astro`
   in a namespace annotated `astro/admin: fairwinds`, which between them match
   the `deployment` and `binding` rulesets in `conf-example.yml`.

No Datadog account is involved: with no credentials astro logs
`Running as DryRun, skipping DataDog update` instead of calling the API, and
that log line is what the smoke test asserts on.

Iterating after a code change is just:

```bash
astro-deploy    # rebuild, reload, restart
kubectl -n astro logs -l app.kubernetes.io/name=astro -f
```

Tear it all down with `astro-cluster-down`.

### Knobs

Every default comes from `[vars]` in `.flox/env/manifest.toml` and can be
overridden in your shell:

| Variable | Default | |
|:--|:--|:--|
| `KIND_CLUSTER_NAME` | `astro-dev` | cluster name |
| `KIND_NODE_IMAGE` | `kindest/node:v1.34.0` | test astro against another Kubernetes version |
| `ASTRO_IMAGE` | `astro:dev` | local image tag |
| `ASTRO_NAMESPACE` | `astro` | where astro is installed |
| `DRY_RUN`, `OWNER`, `DEFINITIONS_PATH` | see `README.md` | astro's own configuration |
| `ASTRO_DEV_SYSTEM_KUBECONFIG` | unset | `1` keeps your own `KUBECONFIG` |
| `ASTRO_DEV_QUIET` | unset | `1` silences the activation banner |

To point astro at a real Datadog account, set `DD_API_KEY`, `DD_APP_KEY` and
`DRY_RUN=false` — but note that the in-cluster deployment reads its
configuration from the `astro` ConfigMap in `hack/manifests/cm.yaml`, not from
your shell.

## Adding a tool

```bash
flox install <package>          # or edit .flox/env/manifest.toml
```

Commit the resulting `manifest.toml` and `manifest.lock` together so everyone
lands on the same versions.

## Known gaps

`.circleci/config.yml`, `hack/kind/` and `e2e/` are still on the pre-Flox
toolchain (Helm 2/Tiller, `kind get kubeconfig-path`, `yq` v2, Kubernetes
1.15–1.17 node images) and do not run today; see `MODERNIZATION_PLAN.md`.
`hack/dev/` is the supported local path until that work lands.
