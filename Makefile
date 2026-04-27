SHELL := /bin/bash

WEBSITE       ?=
PORT          ?= 8080

INVENTORY_DIR ?= ../../websites-inventory

GITLEAKS   ?= gitleaks
ACTIONLINT ?= actionlint

LEFTHOOK_VERSION ?= 1.7.10
LEFTHOOK_DIR     ?= $(CURDIR)/.bin
LEFTHOOK_BIN     ?= $(LEFTHOOK_DIR)/lefthook

.PHONY: help preview list-websites \
	lint secrets-scan-staged lefthook-bootstrap lefthook-install lefthook-run lefthook

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "; printf "Usage: make <target>\n\nTargets:\n"} /^[a-zA-Z0-9_.-]+:.*## / {printf "  %-24s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

list-websites: ## List available websites from the inventory
	@ls "$(INVENTORY_DIR)"/*.yaml 2>/dev/null \
		| xargs -n1 basename | sed 's/\.yaml$$//' | sed 's/^/  /'

preview: ## Preview a website locally — WEBSITE=<name> required, PORT=8080 (default)
	@[[ -n "$(WEBSITE)" ]] || (echo "Usage: make preview WEBSITE=<name>"; echo ""; $(MAKE) list-websites; exit 1)
	@bash ./scripts/preview.sh "$(WEBSITE)" "$(PORT)"

lint: ## Lint GitHub Actions workflows with actionlint
	@./scripts/hooks/check_required_tools.sh $(ACTIONLINT)
	$(ACTIONLINT)

secrets-scan-staged: ## Scan staged diff for secrets with gitleaks
	@./scripts/hooks/check_required_tools.sh $(GITLEAKS)
	$(GITLEAKS) protect --staged --redact

lefthook-bootstrap: ## Download lefthook binary into ./.bin
	LEFTHOOK_VERSION="$(LEFTHOOK_VERSION)" BIN_DIR="$(LEFTHOOK_DIR)" bash ./scripts/bootstrap_lefthook.sh

lefthook-install: lefthook-bootstrap ## Install git hooks
	@if [ -x "$(LEFTHOOK_BIN)" ] && [ -x ".git/hooks/pre-commit" ] && [ -x ".git/hooks/pre-push" ] && [ -x ".git/hooks/commit-msg" ]; then \
		echo "lefthook hooks already installed"; exit 0; \
	fi
	LEFTHOOK="$(LEFTHOOK_BIN)" "$(LEFTHOOK_BIN)" install

lefthook-run: lefthook-bootstrap ## Run all hooks
	LEFTHOOK="$(LEFTHOOK_BIN)" "$(LEFTHOOK_BIN)" run pre-commit
	@tmp_msg="$$(mktemp)"; \
	echo "chore(hooks): validate commit-msg hook" > "$$tmp_msg"; \
	LEFTHOOK="$(LEFTHOOK_BIN)" "$(LEFTHOOK_BIN)" run commit-msg -- "$$tmp_msg"; \
	rm -f "$$tmp_msg"
	LEFTHOOK="$(LEFTHOOK_BIN)" "$(LEFTHOOK_BIN)" run pre-push

lefthook: lefthook-bootstrap lefthook-install lefthook-run ## Bootstrap, install, and run hooks
