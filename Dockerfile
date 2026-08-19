# syntax=docker/dockerfile:1

# ---- Build stage ------------------------------------------------------------
# Latest stable Rust toolchain; produces a fully static musl binary so the
# runtime stage needs no libc at all and the image can run on any Docker or
# Kubernetes host regardless of the underlying distro.
FROM rust:1-trixie AS builder

# Native-compile for musl on whatever CPU architecture is building the image
# (amd64 or arm64), so multi-arch builds never need a cross-linker.
ARG TARGETARCH
# hadolint ignore=DL3008
RUN set -eu; \
    arch="${TARGETARCH:-}"; \
    if [ -z "$arch" ]; then \
      case "$(uname -m)" in \
        x86_64) arch=amd64 ;; \
        aarch64) arch=arm64 ;; \
        *) echo "unsupported host architecture: $(uname -m)" >&2; exit 1 ;; \
      esac; \
    fi; \
    case "$arch" in \
      amd64) rust_target=x86_64-unknown-linux-musl ;; \
      arm64) rust_target=aarch64-unknown-linux-musl ;; \
      *) echo "unsupported target architecture: $arch" >&2; exit 1 ;; \
    esac; \
    echo "$rust_target" > /tmp/rust_target.txt \
    && rustup target add "$rust_target" \
    && apt-get update \
    # musl-tools left intentionally unpinned: tracks whatever version ships
    # with the floating rust:1-trixie base image.
    && apt-get install -y --no-install-recommends musl-tools \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app

# Build dependencies first so they're cached separately from application code.
COPY Cargo.toml Cargo.lock ./
RUN mkdir src \
    && echo "fn main() {}" > src/main.rs \
    && echo "" > src/lib.rs \
    && cargo build --release --target "$(cat /tmp/rust_target.txt)" \
    && rm -rf "target/$(cat /tmp/rust_target.txt)/release/deps/"*rust*service* \
              "target/$(cat /tmp/rust_target.txt)/release/rust-service" \
              "target/$(cat /tmp/rust_target.txt)/release/.fingerprint/"*rust*service*

COPY src ./src
RUN cargo build --release --target "$(cat /tmp/rust_target.txt)" \
    && cp "target/$(cat /tmp/rust_target.txt)/release/rust-service" /usr/local/bin/rust-service

# ---- Runtime stage ------------------------------------------------------------
# Distroless static: no shell, no package manager, non-root by default.
FROM gcr.io/distroless/static-debian12:nonroot AS runtime

WORKDIR /app
COPY --from=builder /usr/local/bin/rust-service /app/rust-service

ENV PORT=8080
EXPOSE 8080
# Numeric UID/GID (distroless's "nonroot" user, 65532:65532): resolvable even
# without /etc/passwd lookups and matches Kubernetes runAsUser conventions.
USER 65532:65532

ENTRYPOINT ["/app/rust-service"]
