# OpenClaw Cluster Manager — Makefile
# Convenient entry points for development and release.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

IMAGE   ?= openclaw-cluster
TAG     ?= $(shell cat VERSION 2>/dev/null || echo dev)
COUNT   ?= 1
RANGE   ?= 1-1

# ---- Help -------------------------------------------------------------------
.PHONY: help
help: ## Show this help message
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ---- Quality gates ----------------------------------------------------------
.PHONY: lint lint-shellcheck lint-shfmt
lint: lint-shellcheck lint-shfmt ## Run all linters

lint-shellcheck: ## Run shellcheck on all .sh files
	./scripts/lint.sh shellcheck

lint-shfmt: ## Check shfmt compliance
	./scripts/lint.sh shfmt

.PHONY: format
format: ## Auto-format shell files with shfmt
	./scripts/lint.sh format

.PHONY: test test-unit
test: test-unit ## Run unit test suite

test-unit: ## Run bats unit tests
	./scripts/test-unit.sh

.PHONY: test-integration
test-integration: ## Run bats integration tests (requires Docker)
	@command -v docker >/dev/null 2>&1 || { echo "docker required" >&2; exit 1; }
	@command -v bats    >/dev/null 2>&1 || { echo "bats required" >&2;    exit 1; }
	bats tests/integration/

# ---- Build / Run ------------------------------------------------------------
.PHONY: build
build: ## Build the Docker image
	docker build -t $(IMAGE):$(TAG) -t $(IMAGE):latest -f Dockerfile.openclaw-chrome .

.PHONY: run
run: ## Launch the interactive cluster manager
	./openclaw-cluster.sh

.PHONY: init
init: ## Initialize cluster (make init COUNT=3)
	./openclaw-cluster.sh init $(COUNT)

.PHONY: status
status: ## Show cluster status
	./openclaw-cluster.sh status

.PHONY: clean
clean: ## Remove build artifacts and dangling images
	./scripts/lint.sh clean
	docker image prune -f

# ---- Release ----------------------------------------------------------------
.PHONY: version
version: ## Print current version
	@cat VERSION

.PHONY: tag
tag: ## Create a git tag from VERSION
	git diff --quiet || { echo "Working tree dirty" >&2; exit 1; }
	git tag -s "v$$(cat VERSION)" -m "Release v$$(cat VERSION)"

# ---- Self-check -------------------------------------------------------------
.PHONY: doctor
doctor: ## Verify the project structure is intact
	@./scripts/lint.sh doctor
