# make help lists every target. Offline targets: install lint test validate scan run. Azure targets: up deploy smoke break down.
PYTHON ?= $(shell command -v python3.13 || command -v python3.12 || command -v python3)
VENV := .venv
PY := $(VENV)/bin/python
STAMP := $(VENV)/.installed
TF_ENV := infra/environments/dev
CHECKOV ?= uvx --from checkov==3.3.30 checkov
PORT ?= 8000

-include .env
export

.PHONY: help install env run run-denied lint format test test-e2e test-azure audit check validate tf-test scan \
        docker-build docker-smoke up deploy smoke audit-config down clean

help: ## list the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | sort

$(STAMP): requirements-dev.lock pyproject.toml
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install -q --require-hashes -r requirements-dev.lock
	$(VENV)/bin/pip install -q --no-deps -e .
	touch $@

install: $(STAMP) ## create .venv from the lock file

env:
	@[ -f .env ] || { cp .env.example .env; echo "created .env from .env.example"; }

run: $(STAMP) ## serve the app on localhost with the in-memory backend (no Azure needed); BACKEND=azure uses az login
	BACKEND=$${BACKEND:-memory} $(VENV)/bin/gunicorn --bind 127.0.0.1:$(PORT) "secretless_app.interfaces.wsgi:create()"

run-denied: $(STAMP) ## the same, with the blob role "removed": uploads answer 502 AuthorizationPermissionMismatch
	BACKEND=memory MEMORY_DENY=blob $(VENV)/bin/gunicorn --bind 127.0.0.1:$(PORT) "secretless_app.interfaces.wsgi:create()"

lint: $(STAMP) ## ruff, mypy, import-linter, shellcheck, terraform fmt, tflint
	$(VENV)/bin/ruff check .
	$(VENV)/bin/ruff format --check .
	$(VENV)/bin/mypy
	$(VENV)/bin/lint-imports
	shellcheck -x -P SCRIPTDIR scripts/*.sh
	terraform fmt -check -recursive infra
	@if command -v tflint >/dev/null; then \
	  tflint --init --config "$(CURDIR)/.tflint.hcl" >/dev/null && tflint --chdir infra --recursive --minimum-failure-severity=warning --config "$(CURDIR)/.tflint.hcl"; \
	else echo "WARNING: tflint is not installed here; the CI workflow runs it"; fi

format: $(STAMP) ## apply ruff's formatting and safe fixes, and terraform fmt
	$(VENV)/bin/ruff check --fix .
	$(VENV)/bin/ruff format .
	terraform fmt -recursive infra

# Unit tests need no Azure. The domain and application must stay at 95% coverage or more.
test: $(STAMP) ## unit and end-to-end tests with coverage (no Azure needed)
	$(PY) -m pytest tests/unit tests/e2e --cov=secretless_app --cov-report=term
	$(PY) -m coverage report --include='src/secretless_app/domain/*,src/secretless_app/application/*' --fail-under=95

test-e2e: $(STAMP) ## only the tests that start the real server
	$(PY) -m pytest tests/e2e -m e2e

test-azure: $(STAMP) ## the real adapters against the deployed resources (after make deploy; needs az login)
	RUN_AZURE_TESTS=1 $(PY) -m pytest tests/integration -m azure

audit: $(STAMP) ## check the locked dependencies for known vulnerabilities
	$(VENV)/bin/pip-audit --no-deps --disable-pip -r requirements-dev.lock

validate: ## terraform init -backend=false and validate for the environment, then terraform test for every module and the environment
	cd $(TF_ENV) && terraform init -backend=false -input=false >/dev/null && terraform validate
	$(MAKE) --no-print-directory tf-test

tf-test: ## terraform test: plans and applies each module and the environment against a mocked azurerm provider (no credentials)
	@set -e; for dir in infra/modules/* $(TF_ENV); do \
	  echo "== terraform test $$dir"; \
	  (cd $$dir && terraform init -backend=false -input=false >/dev/null && terraform test); \
	done

scan: ## checkov over infra/ (the skips and their reasons are in .checkov.yaml and inline)
	$(CHECKOV) --config-file .checkov.yaml --quiet --compact

check: lint test validate ## everything that needs no Azure

docker-build: ## build the container image
	docker build -t azure-secretless-app:dev .

docker-smoke: docker-build ## run the image with the in-memory backend and curl it
	scripts/docker-smoke.sh azure-secretless-app:dev

up: ## provision the Azure resources (needs az login; billed, see README Deploy)
	scripts/provision.sh

deploy: ## build the image in ACR and roll the container app to it
	scripts/build-and-deploy.sh

smoke: ## health, upload and the role listing against the deployed app
	scripts/smoke.sh

audit-config: ## step 4: search the deployed configuration and the source for a key, password or connection string
	scripts/audit-config.sh

down: ## delete the resource group, purge the vault, remove the budget
	scripts/teardown.sh

clean:
	rm -rf $(VENV) .pytest_cache .mypy_cache .ruff_cache .import_linter_cache .coverage dist
	find infra -name .terraform -type d -prune -exec rm -rf {} +
