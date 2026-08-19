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

## Project layout

```
src/
  main.rs        # binary entrypoint: binds the socket, wires up graceful shutdown
  lib.rs         # library crate root, re-exports `app`
  app.rs         # router + handlers, testable without a real socket
tests/
  health.rs      # integration tests against the router (tower::ServiceExt::oneshot)
.devcontainer/   # VS Code Dev Container definition
k8s/             # Deployment + Service manifests
Dockerfile       # production, multi-stage container build
docker-compose.yml
Makefile         # binary / cargo / container build targets
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
kubectl apply -f k8s/deployment.yaml -f k8s/service.yaml
kubectl port-forward svc/rust-service 8080:80
curl http://localhost:8080/healthz
```

`k8s/deployment.yaml` sets `runAsNonRoot`, a read-only root filesystem, drops all
capabilities, and wires `livenessProbe`/`readinessProbe` to `/healthz` and `/readyz`.

## Container image design

- **Builder stage**: `rust:1-trixie` (the official Rust image's `latest` tag, currently
  Debian trixie) natively compiles a fully static binary for the build machine's
  architecture (`x86_64-unknown-linux-musl` or `aarch64-unknown-linux-musl`, detected
  from `TARGETARCH`/`uname -m`), so the runtime stage needs no glibc at all and
  multi-arch builds (e.g. via `docker buildx build --platform linux/amd64,linux/arm64`)
  never need a cross-linker.
- **Runtime stage**: `gcr.io/distroless/static-debian12:nonroot` — a few MB, no
  shell, no package manager, and runs as the non-root `nonroot` user by default.
- Dependency compilation is cached in its own Docker layer, so editing `src/`
  doesn't force a full crate-dependency rebuild.

## CI

`.github/workflows/ci.yml` runs on every push/PR: `cargo fmt --check`, `cargo clippy
-D warnings`, `cargo test`, then a container build to catch `Dockerfile` regressions.
Dependabot (`.github/dependabot.yml`) keeps cargo, Docker, Dev Container, and Action
versions current.

## License

MIT — see [LICENSE](LICENSE).
