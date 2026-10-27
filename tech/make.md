# GNU Make

*The one command per job: `make test`, `make lint`, `make up`. Pinned here: GNU Make 3.81 (the version macOS ships).*

## What it is

Make is a tool that runs named recipes. You write them in a file called `Makefile`. Each recipe is a **target** (a name), its **prerequisites** (what must exist or run first) and a **recipe** (the shell commands). `make test` finds the target `test` and runs it. The Makefile gives a project one memorable command per job.

## Why this repository uses it

The template asks that a reader only needs `make run`, `make test` and a few more. The Makefile is also what CI runs, so CI and a developer run the same commands.

## Where it appears

| File | What it does with it |
|---|---|
| `Makefile` | All targets. |

## How it works underneath

Make reads the Makefile and builds a graph of targets. When you ask for a target, it first builds each prerequisite, then runs the recipe. If a target is a **file** and it is newer than its prerequisites, Make skips it; that is how `.venv/.installed` avoids reinstalling the packages each time. A target that is only a name, not a file, is listed under `.PHONY` so Make always runs it.

Every line of a recipe is run in its own shell. Lines must start with a **tab**. `$(VAR)` is a Make variable; `$$` writes a literal `$` for the shell (`$$RANDOM`). `?=` sets a variable only if it is not already set. `-include .env` reads variables from a file if it exists, and `export` passes all Make variables to the commands. A `## text` comment after a target is read by the `help` target to print a menu.

The Makefile on this Mac is run by GNU Make 3.81, so it uses no newer features.

## Walkthrough of this repository's use

### Variables and includes

```make
PYTHON ?= $(shell command -v python3.13 || command -v python3.12 || command -v python3)
VENV := .venv
PY := $(VENV)/bin/python
STAMP := $(VENV)/.installed
TF_ENV := infra/environments/dev
CHECKOV ?= uvx --from checkov==3.3.30 checkov
PORT ?= 8000
```

`PYTHON ?= $(shell command -v python3.13 || ...)` picks the newest Python on the machine unless you set `PYTHON`. `STAMP := $(VENV)/.installed` uses `:=` (evaluate now) for a fixed value. `CHECKOV ?= uvx --from checkov==3.3.30 checkov` runs checkov through `uvx` unless you provide your own command.

```make
-include .env
export
```

`-include .env` reads variables from `.env` if the file exists (the leading `-` ignores a missing file). `export` passes all Make variables to the commands.

### The help target

```make
help: ## list the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | sort
```

The recipe line reads the Makefile itself: `grep -E '^[a-z-]+:.*## '` picks lines of the form `target: ... ## text` and `sed` turns them into `target<TAB>text`. That is why every target carries a `## description`.

### A file target that avoids repeated installs

```make
$(STAMP): requirements-dev.lock pyproject.toml
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install -q --require-hashes -r requirements-dev.lock
	$(VENV)/bin/pip install -q --no-deps -e .
	touch $@
```

The target is a file. It depends on the lock file and `pyproject.toml`, so Make runs the recipe only when one of them is newer. The recipe creates the environment, installs from the lock and touches the stamp. `install: $(STAMP)` is just a friendly name for it.

### Targets that use the stamp

```make
test: $(STAMP) ## unit and end-to-end tests with coverage (no Azure needed)
	$(PY) -m pytest tests/unit tests/e2e --cov=secretless_app --cov-report=term
	$(PY) -m coverage report --include='src/secretless_app/domain/*,src/secretless_app/application/*' --fail-under=95
```

`test: $(STAMP)` means "make sure the environment exists first". `$(PY)` is `.venv/bin/python`. The test target runs pytest with coverage and then enforces 95 percent on the two inner layers.

### Terraform targets

```make
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
```

`cd $(TF_ENV) && terraform init -backend=false ... && terraform validate` joins steps with `&&` on one line because each recipe line is its own shell. `$(MAKE) --no-print-directory tf-test` calls Make again for the next target. `tf-test` loops over every module folder with a shell `for`; `$$dir` has two dollar signs so Make passes one `$` to the shell. `set -e` stops at the first failure.

### Azure targets

```make
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
```

`up`, `deploy`, `smoke`, `audit-config` and `down` each call one script. They are listed in `.PHONY` with the others because none of them is a file.

## Try it yourself

Print the menu that the `##` comments produce.

```bash
make help
```

You should see something like this:

```text
audit	check the locked dependencies for known vulnerabilities
audit-config	step 4: search the deployed configuration and the source for a key, password or connection string
check	everything that needs no Azure
deploy	build the image in ACR and roll the container app to it
docker-build	build the container image
docker-smoke	run the image with the in-memory backend and curl it
down	delete the resource group, purge the vault, remove the budget
format	apply ruff's formatting and safe fixes, and terraform fmt
help	list the targets
install	create .venv from the lock file
lint	ruff, mypy, import-linter, shellcheck, terraform fmt, tflint
run	serve the app on localhost with the in-memory backend (no Azure needed); BACKEND=azure uses az login
run-denied	the same, with the blob role "removed": uploads answer 502 AuthorizationPermissionMismatch
scan	checkov over infra/ (the skips and their reasons are in .checkov.yaml and inline)
...
validate	terraform init -backend=false and validate for the environment, then terraform test for every module and the environment
```

Show what `make test` would run, without running it.

```bash
make -n test | head -3
```

You should see something like this:

```text
.venv/bin/python -m pytest tests/unit tests/e2e --cov=secretless_app --cov-report=term
.venv/bin/python -m coverage report --include='src/secretless_app/domain/*,src/secretless_app/application/*' --fail-under=95
```

See that nothing needs installing when the stamp is current (prints nothing or the commands).

```bash
make -n install
```

You should see something like this:

```text
make: Nothing to be done for `install'.
```

Check the version.

```bash
make --version | head -1
```

You should see something like this:

```text
GNU Make 3.81
```

## Mistakes people make

- Spaces instead of a tab at the start of a recipe line: `*** missing separator`.
- Forgetting `.PHONY`, so a file named `test` would stop `make test` from running.
- Expecting `cd` on one recipe line to affect the next line. Each line is its own shell; join with `&&` or use `cd dir && command`.
- Writing `$RANDOM` instead of `$$RANDOM` and having Make eat the `$`.
- Putting logic in the Makefile that belongs in a script. Long steps live in `scripts/`.

## Check yourself

1. **What are a target, a prerequisite and a recipe?**
   Answer: The name you ask for, what must be built first, and the commands that build it.

2. **Why must recipe lines start with a tab?**
   Answer: That is how Make tells a recipe line from a Make directive.

3. **What does `.PHONY` do?**
   Answer: It marks targets that are names, not files, so they always run.

4. **What does `$$` mean?**
   Answer: A literal dollar sign passed to the shell.

5. **Why does `.venv/.installed` exist?**
   Answer: It is a file target; Make reinstalls only when the lock file or `pyproject.toml` is newer.

## Further reading

- GNU Make manual (3.81 is used on the author's Mac): https://www.gnu.org/software/make/manual/make.html
