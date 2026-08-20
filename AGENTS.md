# AGENTS.md

Instructions for AI coding agents working in this repository. [README.md](README.md)
is the source of truth for architecture, endpoints, Docker/Kubernetes usage, and
CI/CD/security tooling — read it before making non-trivial changes. This file only
covers what agents need before touching code, plus gotchas not written down
elsewhere.

## Architecture

Single Rust crate (`rust_service`, edition 2024): an Axum + Tokio HTTP service
shipped as a distroless container that runs unmodified on Docker, Podman, or
Kubernetes.

- `src/main.rs` — binary entry point only: binds the socket, wires graceful shutdown.
- `src/app.rs` — the `Router` and its handlers. No socket is bound here, so it's
  directly testable via `tower::ServiceExt::oneshot`.
- `src/config.rs` — pure env-parsing helpers (e.g. `port_from_env`).
- `tests/health.rs` — integration tests against the router.
- `Dockerfile` — multi-stage: `rust:1-trixie` builder (static musl binary,
  arch auto-detected) → `gcr.io/distroless/static-debian12:nonroot` runtime.
- `k8s/` — Namespace + ServiceAccount + Deployment + Service + PodDisruptionBudget.
- `.github/workflows/` — `ci.yml` (fmt/clippy/test/container/smoke-test),
  `security.yml` (cargo-deny/hadolint/gitleaks/trivy), `cd.yml` (multi-arch
  GHCR publish, cosign signing, SBOM, releases).

## Build, Test, and Verify

Use the `Makefile` targets, not raw `cargo`/`docker` commands, so local runs match CI:

| Task | Command |
|------|---------|
| Format check | `make fmt` |
| Lint (denies warnings) | `make lint` |
| Unit + integration tests | `make test` |
| fmt + lint + test | `make cargo` |
| Build the container image | `make container` |
| Build + black-box HTTP-test the image | `make smoke-test` |
| Full pipeline (cargo + container + smoke-test) | `make all` |
| All security scans (cargo-deny, hadolint, gitleaks, trivy) | `make security` |
| List every target | `make help` |

`CONTAINER_ENGINE` auto-detects podman vs docker; override with e.g.
`make container CONTAINER_ENGINE=docker`.

**Definition of done:** `make cargo` passes. If you touched the `Dockerfile`,
`k8s/*.yaml`, or `scripts/smoke-test.sh`, also run `make smoke-test`. If you
touched dependencies, the `Dockerfile`, or `k8s/*.yaml`, also run the matching
`make <x>-scan` / `make deny` target — don't just eyeball it.

## Conventions

- **Env/config parsing stays pure.** Don't read `std::env::var` inside logic
  you want to unit test — take `Option<&str>` and let the caller supply it
  (see `src/config.rs`). Reading real env vars directly in tests causes races
  across parallel `cargo test` threads.
- **New routes need three things:** a handler in `src/app.rs`, an integration
  test in `tests/health.rs`, and a check in `scripts/smoke-test.sh` if it's
  runtime/container-visible behavior (health, readiness, etc.).
- **Don't add `cargo-audit`.** `cargo-deny`'s `[advisories]` check (`deny.toml`)
  already covers the RustSec database; it would be a redundant tool.
- **Suppressions must be justified, never silent.** `.trivyignore` and
  `deny.toml`'s license allow-list already carry a comment explaining every
  entry. Follow the same pattern for any new one — don't add an ID just to
  make a scan pass without writing down why it's safe to ignore.
- **The Dockerfile's dependency-caching stage is fragile.** It builds a dummy
  `src/main.rs`/`src/lib.rs` to cache dependency compilation, then deletes the
  stale build artifacts before copying in real `src/`. That delete must cover
  *both* the bin and the lib crate outputs (`deps/*rust*service*`, not just
  the binary) or the real build silently links against the stale empty lib.
  If you touch that `RUN` block, run `make smoke-test` after — `/` returning
  real JSON (not a panic) is the signal it worked.
- **Image tags:** `cd.yml` publishes `edge`/`sha-<short>` from `main` and
  `X.Y.Z`/`X.Y`/`X`/`latest` from `vX.Y.Z` git tags. `k8s/deployment.yaml`
  intentionally references `:edge`, not `:latest` (see the comment above its
  `image:` line) — keep it that way. Keep a release git tag's version in sync
  with `Cargo.toml`'s `version`.
- **The Prometheus recorder in `src/app.rs` is process-global.** `app()` is
  called once per test (dozens of times per test binary) plus once in `main`;
  it builds the `PrometheusMetricLayer`/`PrometheusHandle` pair exactly once
  via a `OnceLock` and clones it on every call. If you ever stop reusing that
  `OnceLock`, calling `PrometheusMetricLayer::pair()` more than once per
  process will panic — you'll see it immediately as every test but the first
  failing.
- **Devcontainer feature version bumps aren't covered by CI.** GitHub Actions
  never builds `.devcontainer/devcontainer.json` — only the production
  `Dockerfile` — so a Dependabot bump to a devcontainer feature can break
  local development silently. Case in point: bumping
  `ghcr.io/devcontainers/features/docker-in-docker` from `2` to `4` broke the
  devcontainer build, because v4 hard-fails when `moby: true` on Debian
  trixie (our base image's codename) — `moby-cli` packages no longer exist
  for trixie. Fix/keep as `"moby": false`, which installs real Docker CE
  packages instead (upstream's own trixie test scenario uses the same
  setting). When bumping any `ghcr.io/devcontainers/features/*` version,
  actually test the devcontainer build (or at least check the feature's
  `NOTES.md`/`scenarios.json` upstream) instead of merging on green CI alone.

## Reference

Don't duplicate these — read them: [README.md](README.md) (full docs),
[deny.toml](deny.toml) (dependency/license policy),
[.trivyignore](.trivyignore) (justified scan suppressions).
