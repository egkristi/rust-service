.PHONY: all binary cargo fmt lint test container smoke-test deny hadolint secrets-scan dockerfile-scan k8s-scan container-scan security run container-run container-stop clean help

CARGO ?= cargo
IMAGE_NAME ?= rust-service
IMAGE_TAG ?= dev
CONTAINER_ENGINE ?= $(shell command -v podman >/dev/null 2>&1 && echo podman || echo docker)
PORT ?= 8080

all: cargo container smoke-test ## Run the full cargo workflow, build the image, and smoke-test it

binary: ## Build a native release binary with cargo (target/release/rust-service)
	$(CARGO) build --release

cargo: fmt lint test ## Run format check, lint, and tests

fmt: ## Check formatting
	$(CARGO) fmt --all -- --check

lint: ## Run clippy with warnings denied
	$(CARGO) clippy --all-targets --all-features -- -D warnings

test: ## Run the test suite
	$(CARGO) test --all-targets

container: ## Build the production container image (docker or podman)
	$(CONTAINER_ENGINE) build -t $(IMAGE_NAME):$(IMAGE_TAG) .

smoke-test: container ## Build the image and black-box test it over real HTTP
	CONTAINER_ENGINE=$(CONTAINER_ENGINE) IMAGE_NAME=$(IMAGE_NAME) IMAGE_TAG=$(IMAGE_TAG) PORT=$(PORT) ./scripts/smoke-test.sh

deny: ## Check dependency advisories, licenses, bans, and sources (requires cargo-deny)
	cargo deny check

hadolint: ## Lint the Dockerfile for best practices
	$(CONTAINER_ENGINE) run --rm -i hadolint/hadolint < Dockerfile

secrets-scan: ## Scan the repo (incl. git history) for accidentally committed secrets
	$(CONTAINER_ENGINE) run --rm -v $(CURDIR):/repo:ro zricethezav/gitleaks:latest detect --source /repo -v --redact

dockerfile-scan: ## Scan the Dockerfile for security misconfigurations
	$(CONTAINER_ENGINE) run --rm -v $(CURDIR):/repo:ro -w /repo aquasec/trivy:latest config --ignorefile /repo/.trivyignore Dockerfile

k8s-scan: ## Scan Kubernetes manifests for security misconfigurations
	$(CONTAINER_ENGINE) run --rm -v $(CURDIR):/repo:ro -w /repo aquasec/trivy:latest config --ignorefile /repo/.trivyignore k8s/

container-scan: container ## Scan the built image for OS/package vulnerabilities (HIGH/CRITICAL)
	mkdir -p target/security
	$(CONTAINER_ENGINE) save $(IMAGE_NAME):$(IMAGE_TAG) -o target/security/image.tar
	$(CONTAINER_ENGINE) run --rm -v $(CURDIR)/target/security/image.tar:/image.tar:ro aquasec/trivy:latest image --input /image.tar --severity HIGH,CRITICAL

security: deny hadolint secrets-scan dockerfile-scan k8s-scan container-scan ## Run all security scans

run: binary ## Run the native binary locally
	PORT=$(PORT) ./target/release/rust-service

container-run: container ## Build and run the container image, publishing $(PORT)
	$(CONTAINER_ENGINE) run --rm -d -p $(PORT):8080 --name $(IMAGE_NAME) $(IMAGE_NAME):$(IMAGE_TAG)

container-stop: ## Stop the running container started by container-run
	$(CONTAINER_ENGINE) stop $(IMAGE_NAME)

clean: ## Remove build artifacts
	$(CARGO) clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "%-16s %s\n", $$1, $$2}'
