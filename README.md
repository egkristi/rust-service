# rust-service

A batteries-included template for building a Rust HTTP service, developing it in a
VS Code [Dev Container](https://containers.dev/), and shipping it as a small,
non-root container image that runs unmodified on plain Docker/Podman **or**
Kubernetes.

## Features

- [Axum](https://github.com/tokio-rs/axum) + [Tokio](https://tokio.rs/) HTTP service with structured logging (`tracing`)
- Liveness/readiness endpoints and graceful shutdown on `SIGINT`/`SIGTERM`
- VS Code Dev Container with Rust, Docker-in-Docker, and `kubectl`/`helm`/`minikube` preinstalled
- Multi-stage `Dockerfile` producing a statically linked (musl) binary on a
  [distroless](https://github.com/GoogleContainerTools/distroless) runtime image (no shell, no libc, non-root)
- Kubernetes manifests and a `docker-compose.yml` for local runs
- GitHub Actions CI (fmt, clippy, tests, container build) and Dependabot for cargo/docker/devcontainer/action updates
- Security scanning: dependency advisories/licenses (`cargo-deny`), Dockerfile lint
  (`hadolint`), secret scanning (`gitleaks`), and Dockerfile/Kubernetes/image
  vulnerability scanning (`trivy`), all runnable locally and enforced in CI

## Project layout

```
src/
  main.rs        # binary entrypoint: binds the socket, wires up graceful shutdown
  lib.rs         # library crate root, re-exports `app` and `config`
  app.rs         # router + handlers, testable without a real socket
  config.rs      # pure env-parsing helpers, unit-tested without touching real env vars
tests/
  health.rs      # integration tests against the router (tower::ServiceExt::oneshot)
scripts/
  smoke-test.sh  # black-box HTTP tests against the built container image
.devcontainer/   # VS Code Dev Container definition
k8s/             # Namespace + Deployment + Service manifests
Dockerfile       # production, multi-stage container build
docker-compose.yml
Makefile         # binary / cargo / container / smoke-test / security build targets
deny.toml        # cargo-deny: dependency advisories, license policy, source allow-list
.trivyignore     # justified suppressions for trivy config findings
```

## Endpoints

| Method | Path       | Purpose                                   |
|--------|------------|--------------------------------------------|
| GET    | `/`        | Service name/version as JSON               |
| GET    | `/healthz` | Liveness probe (process is up)              |
| GET    | `/readyz`  | Readiness probe (ready to accept traffic)   |

## Configuration

| Env var    | Default | Description                              |
|------------|---------|-------------------------------------------|
| `PORT`     | `8080`  | TCP port the server listens on (`0.0.0.0`) |
| `RUST_LOG` | `info`  | `tracing`/`env_logger`-style filter        |

## Getting started with the Dev Container

1. Install the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) in VS Code.
2. Open this folder in VS Code and choose **Reopen in Container** (or run `Dev Containers: Reopen in Container` from the command palette).
3. The container includes the Rust toolchain (with `clippy`/`rustfmt`), the `x86_64-unknown-linux-musl` target, Docker-in-Docker, and `kubectl`/`helm`/`minikube`, so you can build, test, containerize, and deploy to a local cluster from inside the container.

## Building without the Dev Container

The three build targets — a plain binary, the cargo workflow, and the container image — are wired up in the `Makefile`:

```bash
make binary         # cargo build --release -> target/release/rust-service
make cargo          # fmt --check + clippy -D warnings + test
make container       # build the OCI image with podman or docker (auto-detected)
make container-run   # build and run the image, publishing $PORT (default 8080)
make help            # list all targets
```

Equivalent raw commands:

```bash
cargo build --release
cargo fmt --all -- --check && cargo clippy --all-targets --all-features -- -D warnings && cargo test

docker build -t rust-service:dev .          # or: podman build -t rust-service:dev .
docker run --rm -p 8080:8080 rust-service:dev
```

`CONTAINER_ENGINE` can be overridden, e.g. `make container CONTAINER_ENGINE=podman`.

## Testing

Three layers of tests cover the service from handler logic up to the shipped container image:

- **Unit tests** in `src/app.rs` and `src/config.rs` exercise handlers and env-var parsing
  directly, with no HTTP or process-environment involved (env parsing takes an `Option<&str>`
  parameter instead of reading `std::env` directly, so tests can't race on real env vars).
- **Integration tests** in `tests/health.rs` drive the real `axum::Router` through
  `tower::ServiceExt::oneshot` — status codes, JSON bodies, response headers, disallowed
  HTTP methods, unknown routes, and concurrent requests — without binding a socket.
- **Container smoke tests** in `scripts/smoke-test.sh` build/run the actual image with
  Docker or Podman and verify it over real HTTP (`/`, `/healthz`, `/readyz`, a 404 route)
  plus that the process runs as the non-root `65532:65532` user.

```bash
cargo test           # unit + integration tests
make smoke-test      # build the image and black-box test the running container
make all             # fmt + clippy + test + container build + smoke test
```

CI (`.github/workflows/ci.yml`) runs all three layers on every push/PR.

## Running with Docker Compose

```bash
docker compose up --build
curl http://localhost:8080/healthz
```

## Running on Kubernetes

The image is a static binary on a distroless base with no shell and no root user,
so it satisfies typical cluster Pod Security Standards out of the box. Build/push
the image to a registry your cluster can reach, then:

```bash
kubectl apply -f k8s/namespace.yaml -f k8s/deployment.yaml -f k8s/service.yaml
kubectl port-forward -n rust-service svc/rust-service 8080:80
curl http://localhost:8080/healthz
```

`k8s/deployment.yaml` runs in its own `rust-service` namespace and sets pod- and
container-level `securityContext` (`runAsNonRoot`, numeric `runAsUser`/`runAsGroup`,
a read-only root filesystem, `RuntimeDefault` seccomp, all capabilities dropped),
and wires `livenessProbe`/`readinessProbe` to `/healthz` and `/readyz`.

## Container image design

- **Builder stage**: `rust:1-trixie` (the official Rust image's `latest` tag, currently
  Debian trixie) natively compiles a fully static binary for the build machine's
  architecture (`x86_64-unknown-linux-musl` or `aarch64-unknown-linux-musl`, detected
  from `TARGETARCH`/`uname -m`), so the runtime stage needs no glibc at all and
  multi-arch builds (e.g. via `docker buildx build --platform linux/amd64,linux/arm64`)
  never need a cross-linker.
- **Runtime stage**: `gcr.io/distroless/static-debian12:nonroot` — a few MB, no
  shell, no package manager. Runs as the numeric `65532:65532` (distroless's
  `nonroot` user) instead of the named user, since numeric IDs resolve without
  an `/etc/passwd` lookup and match Kubernetes `runAsUser` conventions.
- Dependency compilation is cached in its own Docker layer, so editing `src/`
  doesn't force a full crate-dependency rebuild.

## CI

`.github/workflows/ci.yml` runs on every push/PR: `cargo fmt --check`, `cargo clippy
-D warnings`, `cargo test`, then a container build plus `scripts/smoke-test.sh` against
the built image to catch `Dockerfile`/runtime regressions.
Dependabot (`.github/dependabot.yml`) keeps cargo, Docker, Dev Container, and Action
versions current.

## Security

`.github/workflows/security.yml` runs on every push/PR plus a weekly schedule (to
catch newly disclosed CVEs even without code changes):

| Tool | Checks | Local command |
|------|--------|----------------|
| [`cargo-deny`](https://embarkstudios.github.io/cargo-deny/) | RustSec advisories, license allow-list (`deny.toml`), banned/duplicate deps, untrusted sources | `make deny` |
| [`hadolint`](https://github.com/hadolint/hadolint) | Dockerfile best practices | `make hadolint` |
| [`gitleaks`](https://github.com/gitleaks/gitleaks) | Secrets committed to the repo or its git history | `make secrets-scan` |
| [`trivy config`](https://trivy.dev/) | Dockerfile and Kubernetes manifest security misconfigurations | `make dockerfile-scan`, `make k8s-scan` |
| [`trivy image`](https://trivy.dev/) | OS/package vulnerabilities (HIGH/CRITICAL) in the built container image | `make container-scan` |

```bash
make security   # run every scan above locally (uses podman or docker)
```

Suppressions are recorded, never silent: `deny.toml` only allows the specific
permissive licenses this crate's dependency tree actually uses, and `.trivyignore`
justifies the one intentional exception (no `HEALTHCHECK`, since the distroless
runtime image has no shell to run one — Kubernetes probes cover that instead).
The container-image scan also uploads a SARIF report to GitHub's Security tab.

## License

MIT — see [LICENSE](LICENSE).
