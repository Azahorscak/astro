# Contributing

Issues, whether bugs, tasks, or feature requests are essential for keeping astro great. We believe it should be as easy as possible to contribute changes that get things working in your environment. There are a few guidelines that we need contributors to follow so that we can keep on top of things.

## Code of Conduct

This project adheres to a [code of conduct](CODE_OF_CONDUCT.md). Please review this document before contributing to this project.

## Project Structure

Astro is built using the [Kubernetes Go client](https://github.com/kubernetes/client-go) that makes use of the [Kubernetes Api](https://kubernetes.io/docs/reference/using-api/api-concepts/).  The project consists of a collection of controllers that watch for Kubernetes object updates, and sends these updates as events to handlers, which interact with the [Datadog Api](https://docs.datadoghq.com/api/) to manage the lifecycle of monitors.

## Getting Started

We label issues with the ["good first issue" tag](https://github.com/FairwindsOps/astro/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) if we believe they'll be a good starting point for new contributors. If you're interested in working on an issue, please start a conversation on that issue, and we can help answer any questions as they come up.

## Setting Up Your Development Environment

astro uses a [Flox](https://flox.dev) environment that pins the Go toolchain,
the linters, and `kubectl` + `kind`. [DEVELOPMENT.md](DEVELOPMENT.md) is the
full reference; the short version is:

```
git clone https://github.com/fairwindsops/astro && cd astro
flox activate
```

### Prerequisites
* [Flox](https://flox.dev/docs/install-flox/), which supplies everything else.
* A container runtime (Docker, OrbStack, Colima, or podman) if you want to use
  `kind`. Flox cannot ship a runtime daemon.
* Access to a Kubernetes cluster. `astro-cluster-up` creates a local kind
  cluster for you; anything in `~/.kube/config` or `$KUBECONFIG` works too.

### Running it
* `astro-build` builds `bin/astro`, or run it straight from source with
  `go run main.go`.
* `astro-demo` creates a kind cluster and installs astro on it. astro stays in
  dry-run without Datadog credentials, so this needs no Datadog account.

## Running Tests

The following are all required to pass as part of astro testing:

```
astro-lint    # gofmt, go vet, golangci-lint
astro-test    # go test ./...
```

`astro-smoke` additionally verifies a deployment of astro in the kind cluster.

### Datadog Mocking
We mock the interface for the Datadog API client library in `./pkg/datadog/datadog.go`.
If you're adding a new function to the interface there, you'll need to regenerate the
mocks. `mockgen` comes from the Flox environment, so there is nothing to install:
```
mockgen -source=pkg/datadog/datadog.go -destination=pkg/mocks/datadog_mock.go
```

## Creating a New Issue

If you've encountered an issue that is not already reported, please create an issue that contains the following:

- Clear description of the issue
- Steps to reproduce it
- Appropriate labels

## Creating a Pull Request

Each new pull request should:

- Reference any related issues
- Add tests that show the issues have been solved
- Pass existing tests and linting
- Contain a clear indication of if they're ready for review or a work in progress
- Be up to date and/or rebased on the master branch

## Creating a new release

The steps are:
1. Create a PR for this repo
    1. Bump the version number in:
        1. README.md
    2. Update CHANGELOG.md
    3. Merge your PR
2. Tag the latest branch for this repo
    1. Pull the latest for the `master` branch
    2. Run `git tag $VERSION && git push --tags`
    3. Wait for CircleCI to finish the build for the tag, which pushes images to quay.io and creates a release in github
