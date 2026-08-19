.PHONY: all binary cargo fmt lint test container smoke-test run container-run container-stop clean help

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
