SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

# Single source of truth for all upstream version pins. Re-used by GHA via
# `cat versions.env >> $GITHUB_ENV`, and bumped in-place by the cron workflow.
include versions.env

REGISTRY       ?= ghcr.io
# Derive owner/repo from the local git remote so the image matches the GHCR
# reference for whichever fork/clone you're building from.
REPO_PATH      := $(shell git config --get remote.origin.url 2>/dev/null \
	| sed -E -e 's|.*github\.com[:/]||' -e 's|\.git$$||' \
	| tr '[:upper:]' '[:lower:]')
REPO_PATH      := $(if $(REPO_PATH),$(REPO_PATH),youscan/durable-streams-caddy)
IMAGE          ?= $(REPO_PATH)

# Strip the `caddy-` prefix so a tag like `caddy-v0.2.1` becomes `v0.2.1`.
PLUGIN_TAG     := $(PLUGIN_VERSION:caddy-%=%)
TAG            ?= $(PLUGIN_TAG)
FULL_IMAGE     := $(REGISTRY)/$(IMAGE):$(TAG)

# Immutable tags injected from CI (space-separated), e.g. `v0.2.1-sha-abc1234`.
EXTRA_TAGS     ?=

# When TAG isn't overridden, also tag :latest. Overriding TAG (e.g. for PR
# builds) keeps it single-tag so :latest doesn't get clobbered. EXTRA_TAGS
# is always appended so CI-supplied immutable tags land regardless.
ifeq ($(TAG),$(PLUGIN_TAG))
TAG_LIST       := $(TAG) latest $(EXTRA_TAGS)
else
TAG_LIST       := $(TAG) $(EXTRA_TAGS)
endif
IMAGE_TAGS     := $(foreach t,$(TAG_LIST),-t $(REGISTRY)/$(IMAGE):$(t))

PLATFORMS      ?= linux/amd64,linux/arm64
PORT           ?= 4437
CONTAINER      ?= ds-caddy-dev
VOLUME         ?= ds-caddy-data

TEST_PORT      ?= 14437
TEST_CONTAINER ?= ds-caddy-test

BUILD_ARGS := \
	--build-arg DS_REF=$(PLUGIN_VERSION) \
	--build-arg CADDY_VERSION=$(CADDY_VERSION) \
	--build-arg XCADDY_VERSION=$(XCADDY_VERSION)

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@awk 'BEGIN{FS=":.*##"; printf "Usage: make <target>\n\nTargets:\n"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: version
version: ## Show pinned versions and tags
	@printf 'image:       %s\ntags:       %s\nplugin:      %s\ncaddy:       %s\nxcaddy:      %s\nconformance: %s\nplatforms:   %s\n' \
		'$(REGISTRY)/$(IMAGE)' '$(IMAGE_TAGS)' '$(PLUGIN_VERSION)' '$(CADDY_VERSION)' '$(XCADDY_VERSION)' '$(CONFORMANCE_VERSION)' '$(PLATFORMS)'

.PHONY: build
build: ## Build for the current platform
	docker build $(BUILD_ARGS) $(IMAGE_TAGS) .

.PHONY: buildx
buildx: ## Multi-arch build (no push)
	docker buildx build --platform $(PLATFORMS) $(BUILD_ARGS) $(IMAGE_TAGS) .

.PHONY: push
push: ## Multi-arch build and push
	docker buildx build --platform $(PLATFORMS) $(BUILD_ARGS) $(IMAGE_TAGS) --push .

.PHONY: smoke
smoke: build ## Verify the plugin is linked into the built image
	docker run --rm $(FULL_IMAGE) caddy list-modules | grep -q '^http.handlers.durable_streams$$'
	@echo "ok: http.handlers.durable_streams present"

.PHONY: test
test: build ## Run @durable-streams/server-conformance-tests against the built image
	@trap 'docker rm -f $(TEST_CONTAINER) >/dev/null 2>&1 || true' EXIT INT TERM; \
	docker rm -f $(TEST_CONTAINER) >/dev/null 2>&1 || true; \
	docker run --rm -d --name $(TEST_CONTAINER) \
		-p $(TEST_PORT):4437 \
		-v $(CURDIR)/tests/Caddyfile.test:/etc/caddy/Caddyfile:ro \
		$(FULL_IMAGE) >/dev/null; \
	echo "waiting for http://localhost:$(TEST_PORT)..."; \
	for i in $$(seq 1 50); do \
		curl -s -o /dev/null --connect-timeout 1 http://localhost:$(TEST_PORT) && break; \
		sleep 0.2; \
	done; \
	cd tests && \
	(npm ci --silent --no-fund --no-audit 2>/dev/null || npm install --silent --no-fund --no-audit) && \
	DS_URL=http://localhost:$(TEST_PORT) npm test --silent

.PHONY: run
run: build ## Run the container in the foreground on $(PORT)
	docker run --rm -it --name $(CONTAINER) \
		-p $(PORT):4437 \
		-v $(VOLUME):/data \
		$(FULL_IMAGE)

.PHONY: up
up: build ## Run the container detached
	docker run --rm -d --name $(CONTAINER) \
		-p $(PORT):4437 \
		-v $(VOLUME):/data \
		$(FULL_IMAGE)
	@echo "running: http://localhost:$(PORT)/v1/stream/*"

.PHONY: down
down: ## Stop and remove the local container
	-docker rm -f $(CONTAINER) >/dev/null 2>&1 || true

.PHONY: logs
logs: ## Tail container logs
	docker logs -f $(CONTAINER)

.PHONY: clean
clean: down ## Remove the local image and named volume
	-docker rmi $(FULL_IMAGE) >/dev/null 2>&1 || true
	-docker volume rm $(VOLUME) >/dev/null 2>&1 || true
