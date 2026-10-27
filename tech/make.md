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

### Every line, in order

This part walks through every file this note is responsible for, from the first non-blank line to the last, in blocks. Each block shows the lines (the numbers say where they sit in the file) and then explains them. New ideas are explained at the first place they are needed; later blocks use them without repeating the explanation.

#### `Makefile`

78 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 8**

```make
# make help lists every target. Offline targets: install lint test validate scan run. Azure targets: up deploy smoke break down.
PYTHON ?= $(shell command -v python3.13 || command -v python3.12 || command -v python3)
VENV := .venv
PY := $(VENV)/bin/python
STAMP := $(VENV)/.installed
TF_ENV := infra/environments/dev
CHECKOV ?= uvx --from checkov==3.3.30 checkov
PORT ?= 8000
```

**New idea.** A **port** is a number between 1 and 65535 that tells the computer which program on it should receive a network connection. An address such as `127.0.0.1:8000` means "this computer, port 8000"; `127.0.0.1` is the address a computer uses to talk to itself.

**New idea.** An **environment variable** is a named text value that the operating system hands to every program it starts, such as `PORT=8080`. It is the usual way to configure a program without changing its code, and the way a deployment passes settings that differ between machines.

**New idea.** A **virtual environment** is a private folder holding a copy of the Python interpreter and the libraries installed for one project. It keeps the project's libraries separate from the rest of the machine, so two projects can use different versions of the same library.

**New idea.** A **lock file** records the exact versions (and often the hashes) of every package a project uses, including packages that those packages need. Installing from it gives the same result on every machine and on every day.

**New idea.** A **version number** such as `4.81.0` is read as major.minor.patch. A constraint such as `>=4.81` means "4.81 or newer", and Terraform's `~> 4.81` means "4.81 or newer but below 5.0".

**New idea.** An Azure **region** (such as `westeurope`) is a group of data centers in one geographic area. Where a resource is created decides its latency, its price and which legal rules apply.

- `# make help lists every target. Offline targets: install lint test validate scan run. Azure targets: up deploy`: Comment for the reader: make help lists every target. Offline targets: install lint test validate scan run. Azure targets: up deploy smoke break down.
- `PYTHON ?= $(shell command -v python3.13 || command -v python3.12 || command -v python3)`: A line `NAME := value` sets a variable once, when the Makefile is read. `NAME ?= value` sets it only if it is not already set (so you can override it: `make PORT=9000 run`). `$(NAME)` uses the variable. Sets the variable `PYTHON` (only if not already set). The Python interpreter used to create the virtual environment: the first of `python3.13`, `python3.12`, `python3` that exists (`command -v` prints a command's location, and `||` tries the next if it fails). `$(shell command)` runs the command when the Makefile is read and inserts its output.
- `VENV := .venv`: Sets the variable `VENV` (once, when the file is read). The folder of the **virtual environment** (a private copy of Python plus the project's libraries).
- `PY := $(VENV)/bin/python`: Sets the variable `PY` (once, when the file is read). The Python inside that environment.
- `STAMP := $(VENV)/.installed`: Sets the variable `STAMP` (once, when the file is read). A marker file inside the environment. It exists once the libraries are installed; make compares its age with the lock file to decide whether to reinstall.
- `TF_ENV := infra/environments/dev`: Sets the variable `TF_ENV` (once, when the file is read). The folder of the Terraform environment that the targets operate on.
- `CHECKOV ?= uvx --from checkov==3.3.30 checkov`: Sets the variable `CHECKOV` (only if not already set). How to run checkov: `uvx` fetches and runs a pinned version on demand. CI overrides the variable (`CHECKOV=checkov`) because it installs checkov itself.
- `PORT ?= 8000`: Sets the variable `PORT` (only if not already set). The local port the web server listens on.

**Lines 10 to 11**

```make
-include .env
export
```

- `-include .env`: `-include .env` reads the file `.env` if it exists (the leading `-` means "no error if it is missing"), and `export` passes every variable to the commands that make runs as environment variables.
- `export`: Marks every variable to be passed to the commands as an environment variable (see the line above).

**Lines 13 to 14**

```make
.PHONY: help install env run run-denied lint format test test-e2e test-azure audit check validate tf-test scan \
        docker-build docker-smoke up deploy smoke audit-config down clean
```

- `.PHONY: help install env run run-denied lint format test test-e2e test-azure audit check validate tf-test scan`: `.PHONY` lists the targets that are tasks, not files. Here are the names.

**Lines 16 to 17**

```make
help: ## list the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | sort
```

**New idea.** A **regular expression** is a compact pattern for matching text: `[a-z]` is one lowercase letter, `+` means one or more, `^` and `$` mark the start and end, `{1,127}` means one to 127 repeats.

- `help: ## list the targets`: **make** is a program that runs named tasks defined in a file called `Makefile`. You run a task with `make <name>`. Each task (a **target**) lists what must be done before it (its **prerequisites**) and the shell commands to run (its **recipe**, whose lines must start with a tab character). A line `name: prerequisites` defines a target. Before running the recipe, make runs every prerequisite that is itself a target. If the target is the name of a *file*, make skips the recipe when the file is newer than all its prerequisites; the targets listed after `.PHONY` are not files, so they always run. Defines the target `help`. Description (shown by `make help`): list the targets. The text after `##` on a target line is a one-line description; the `help` target prints these.
- `@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | sort`: Prints the help. `grep -E` selects (with an extended regular expression) the lines that look like `target: ... ## description`; `$(MAKEFILE_LIST)` is the list of Makefiles; the pipe `|` hands the lines to `sed`, which replaces everything from the colon through `## ` with a tab; `sort` puts them in alphabetical order. A recipe line that starts with `@` is run without printing the command first.

**Lines 19 to 23**

```make
$(STAMP): requirements-dev.lock pyproject.toml
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install -q --require-hashes -r requirements-dev.lock
	$(VENV)/bin/pip install -q --no-deps -e .
	touch $@
```

**New idea.** A **hash** (or *digest*) is a fixed-length fingerprint calculated from some data. The same data always gives the same hash and any change gives a different one, so comparing hashes shows whether a file or an image is exactly the one that was reviewed.

- `$(STAMP): requirements-dev.lock pyproject.toml`: Defines the target `$(STAMP)`. Its prerequisites: `requirements-dev.lock`, `pyproject.toml`. This target is the marker file: it is rebuilt whenever the lock file or `pyproject.toml` is newer than it.
- `$(PYTHON) -m venv $(VENV)`: Creates the virtual environment in the folder `.venv` (`-m venv` runs Python's built-in module for that).
- `$(VENV)/bin/pip install -q --require-hashes -r requirements-dev.lock`: Installs exactly the packages in the lock file. `-q` keeps the output quiet, `-r` reads the list from a file, and `--require-hashes` makes pip refuse any package whose fingerprint (hash) is not recorded in the file, so a tampered or substituted package cannot be installed.
- `$(VENV)/bin/pip install -q --no-deps -e .`: Installs this project itself. `-e` (editable) links the source folder instead of copying it, so edits take effect at once; `--no-deps` stops pip from choosing dependencies on its own, because the lock file already installed exactly the right ones.
- `touch $@`: Creates (or refreshes the time of) the marker file, so make knows the install is up to date. `$@` inside a recipe is the name of the target being built.

**Line 25**

```make
install: $(STAMP) ## create .venv from the lock file
```

- `install: $(STAMP) ## create .venv from the lock file`: Defines the target `install`. Its prerequisites: `$(STAMP)`. Description (shown by `make help`): create .venv from the lock file.

**Lines 27 to 28**

```make
env:
	@[ -f .env ] || { cp .env.example .env; echo "created .env from .env.example"; }
```

- `env:`: Defines the target `env`.
- `@[ -f .env ] || { cp .env.example .env; echo "created .env from .env.example"; }`: If the file `.env` does not exist (`[ -f .env ]` tests that a regular file exists), copy the template to it and say so. `||` means "run the right side only if the left side failed".

**Lines 30 to 31**

```make
run: $(STAMP) ## serve the app on localhost with the in-memory backend (no Azure needed); BACKEND=azure uses az login
	BACKEND=$${BACKEND:-memory} $(VENV)/bin/gunicorn --bind 127.0.0.1:$(PORT) "secretless_app.interfaces.wsgi:create()"
```

**New idea.** An **IP address** such as `10.10.2.4` identifies a computer on a network. A **CIDR range** such as `10.10.2.0/24` names a block of addresses: the number after the slash says how many leading bits are fixed, so `/24` fixes the first three numbers and leaves 256 addresses. Ranges starting `10.`, `172.16.` to `172.31.` and `192.168.` are *private*: they are not reachable from the public internet.

**New idea.** Terraform's **state** is a file in which it records the real resources it created and their ids. Each run compares the code, the state and reality to decide what to change. It may contain sensitive values, so it is never committed; a *backend* is the place where the state is stored.

- `run: $(STAMP) ## serve the app on localhost with the in-memory backend (no Azure needed); BACKEND=azure uses a`: Defines the target `run`. Its prerequisites: `$(STAMP)`. Description (shown by `make help`): serve the app on localhost with the in-memory backend (no Azure needed); BACKEND=azure uses az login.
- `BACKEND=$${BACKEND:-memory} $(VENV)/bin/gunicorn --bind 127.0.0.1:$(PORT) "secretless_app.interfaces.wsgi:create()"`: Starts the web server gunicorn for this one command with the environment variable `BACKEND` set to its current value, or `memory` if unset (`${BACKEND:-memory}` in the shell). `--bind 127.0.0.1:$(PORT)` listens on this machine only. The last argument names the app: the function `create()` in the module `secretless_app.interfaces.wsgi`. In a Makefile a doubled `$$` means a single `$` for the shell, because make would otherwise treat `$` as its own variable syntax.

**Lines 33 to 34**

```make
run-denied: $(STAMP) ## the same, with the blob role "removed": uploads answer 502 AuthorizationPermissionMismatch
	BACKEND=memory MEMORY_DENY=blob $(VENV)/bin/gunicorn --bind 127.0.0.1:$(PORT) "secretless_app.interfaces.wsgi:create()"
```

**New idea.** **Azure Blob Storage** stores files (*blobs*) in a *storage account*. Blobs live in *containers*, which work like top-level folders, and each blob is addressed by account, container and name. (This "container" is not a Docker container.)

**New idea.** A **fake** (or *test double*) is a simple stand-in object used in tests in place of a real service. It behaves like the real one in the ways the test needs, with no network, no account and no cost.

- `run-denied: $(STAMP) ## the same, with the blob role "removed": uploads answer 502 AuthorizationPermissionMism`: Defines the target `run-denied`. Its prerequisites: `$(STAMP)`. Description (shown by `make help`): the same, with the blob role "removed": uploads answer 502 AuthorizationPermissionMismatch.
- `BACKEND=memory MEMORY_DENY=blob $(VENV)/bin/gunicorn --bind 127.0.0.1:$(PORT) "secretless_app.interfaces.wsgi:create()"`: Starts the server with the in-memory fake backend, told to behave as if the blob role were missing (`MEMORY_DENY=blob`), so the denial can be seen without Azure.

**Lines 36 to 45**

```make
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
```

- `lint: $(STAMP) ## ruff, mypy, import-linter, shellcheck, terraform fmt, tflint`: Defines the target `lint`. Its prerequisites: `$(STAMP)`. Description (shown by `make help`): ruff, mypy, import-linter, shellcheck, terraform fmt, tflint.
- `$(VENV)/bin/ruff check .`: Runs ruff's linter on the whole project (`.` is the current folder) and fails if it finds problems.
- `$(VENV)/bin/ruff format --check .`: Checks that every Python file is already formatted the way ruff would format it, without changing any file.
- `$(VENV)/bin/mypy`: Runs the type checker. Which files to check comes from `pyproject.toml`.
- `$(VENV)/bin/lint-imports`: Runs import-linter, which checks the layering rules of the imports.
- `shellcheck -x -P SCRIPTDIR scripts/*.sh`: Runs shellcheck (a checker for shell scripts) on every script. `-x` lets it follow `source`d files, and `-P SCRIPTDIR` tells it to look for them next to each script.
- `terraform fmt -check -recursive infra`: Checks that the Terraform files under `infra` are formatted canonically (`-check` changes nothing, `-recursive` includes sub-folders).
- `@if command -v tflint >/dev/null; then \`: Starts a shell `if`: it tests whether the program `tflint` is installed (`command -v` prints its location; `>/dev/null` throws the output away).
- `tflint --init --config "$(CURDIR)/.tflint.hcl" >/dev/null && tflint --chdir infra --recursive --minimum-failure-severity=warning --config "$(CURDIR)/.`: Then: `tflint --init` downloads the rule plug-ins named in the config file; `&&` means "and, if that worked"; the second command lints everything under `infra` recursively, failing on findings of severity warning or worse. `$(CURDIR)` is the folder make is running in.
- `else echo "WARNING: tflint is not installed here; the CI workflow runs it"; fi`: Otherwise print a warning, so the check is not silently skipped; `fi` ends the `if`.

**Lines 47 to 50**

```make
format: $(STAMP) ## apply ruff's formatting and safe fixes, and terraform fmt
	$(VENV)/bin/ruff check --fix .
	$(VENV)/bin/ruff format .
	terraform fmt -recursive infra
```

- `format: $(STAMP) ## apply ruff's formatting and safe fixes, and terraform fmt`: Defines the target `format`. Its prerequisites: `$(STAMP)`. Description (shown by `make help`): apply ruff's formatting and safe fixes, and terraform fmt.
- `$(VENV)/bin/ruff check --fix .`: Lets ruff fix the problems it can fix safely.
- `$(VENV)/bin/ruff format .`: Rewrites the Python files in ruff's format.
- `terraform fmt -recursive infra`: Rewrites the Terraform files in the canonical format.

**Lines 52 to 55**

```make
# Unit tests need no Azure. The domain and application must stay at 95% coverage or more.
test: $(STAMP) ## unit and end-to-end tests with coverage (no Azure needed)
	$(PY) -m pytest tests/unit tests/e2e --cov=secretless_app --cov-report=term
	$(PY) -m coverage report --include='src/secretless_app/domain/*,src/secretless_app/application/*' --fail-under=95
```

**New idea.** **Code coverage** measures which lines (and branches) of the program were run while the tests ran. A line the tests never reach is untested, so the project requires a high percentage for its core layers.

- `# Unit tests need no Azure. The domain and application must stay at 95% coverage or more.`: Comment for the reader: Unit tests need no Azure. The domain and application must stay at 95% coverage or more.
- `test: $(STAMP) ## unit and end-to-end tests with coverage (no Azure needed)`: Defines the target `test`. Its prerequisites: `$(STAMP)`. Description (shown by `make help`): unit and end-to-end tests with coverage (no Azure needed).
- `$(PY) -m pytest tests/unit tests/e2e --cov=secretless_app --cov-report=term`: Runs the unit and end-to-end tests. `--cov=secretless_app` measures which lines of the package the tests ran, and `--cov-report=term` prints the result in the terminal.
- `$(PY) -m coverage report --include='src/secretless_app/domain/*,src/secretless_app/application/*' --fail-under=95`: Prints the coverage for only the domain and application layers and fails if it is under 95 percent.

**Lines 57 to 58**

```make
test-e2e: $(STAMP) ## only the tests that start the real server
	$(PY) -m pytest tests/e2e -m e2e
```

- `test-e2e: $(STAMP) ## only the tests that start the real server`: Defines the target `test-e2e`. Its prerequisites: `$(STAMP)`. Description (shown by `make help`): only the tests that start the real server.
- `$(PY) -m pytest tests/e2e -m e2e`: Runs only the tests carrying the `e2e` marker.

**Lines 60 to 61**

```make
test-azure: $(STAMP) ## the real adapters against the deployed resources (after make deploy; needs az login)
	RUN_AZURE_TESTS=1 $(PY) -m pytest tests/integration -m azure
```

- `test-azure: $(STAMP) ## the real adapters against the deployed resources (after make deploy; needs az login)`: Defines the target `test-azure`. Its prerequisites: `$(STAMP)`. Description (shown by `make help`): the real adapters against the deployed resources (after make deploy; needs az login).
- `RUN_AZURE_TESTS=1 $(PY) -m pytest tests/integration -m azure`: Runs the tests marked `azure`. The variable `RUN_AZURE_TESTS=1` is the explicit switch they require, so they never run by accident.

**Lines 63 to 64**

```make
audit: $(STAMP) ## check the locked dependencies for known vulnerabilities
	$(VENV)/bin/pip-audit --no-deps --disable-pip -r requirements-dev.lock
```

**New idea.** With **peek-lock**, a receiver takes a message but the broker only hides it under a *lock* for a limited time (30 seconds here). If the receiver *completes* the message it is deleted; if it *abandons* it or the lock expires, the message becomes visible again and is delivered once more, which is why processing must tolerate duplicates.

- `audit: $(STAMP) ## check the locked dependencies for known vulnerabilities`: Defines the target `audit`. Its prerequisites: `$(STAMP)`. Description (shown by `make help`): check the locked dependencies for known vulnerabilities.
- `$(VENV)/bin/pip-audit --no-deps --disable-pip -r requirements-dev.lock`: Checks every package in the lock file against a database of known vulnerabilities. `--no-deps --disable-pip` tell it to audit the file as written and not to install anything.

**Lines 66 to 68**

```make
validate: ## terraform init -backend=false and validate for the environment, then terraform test for every module and the environment
	cd $(TF_ENV) && terraform init -backend=false -input=false >/dev/null && terraform validate
	$(MAKE) --no-print-directory tf-test
```

- `validate: ## terraform init -backend=false and validate for the environment, then terraform test for every mod`: Defines the target `validate`. Description (shown by `make help`): terraform init -backend=false and validate for the environment, then terraform test for every module and the environment.
- `cd $(TF_ENV) && terraform init -backend=false -input=false >/dev/null && terraform validate`: Goes into the environment folder, downloads providers (`init`; `-backend=false` skips remote state, `-input=false` never asks questions; output discarded) and then checks that the configuration is internally consistent (`validate`).
- `$(MAKE) --no-print-directory tf-test`: Runs the `tf-test` target by starting make again (`$(MAKE)` is make itself); `--no-print-directory` suppresses the "entering directory" lines.

**Lines 70 to 74**

```make
tf-test: ## terraform test: plans and applies each module and the environment against a mocked azurerm provider (no credentials)
	@set -e; for dir in infra/modules/* $(TF_ENV); do \
	  echo "== terraform test $$dir"; \
	  (cd $$dir && terraform init -backend=false -input=false >/dev/null && terraform test); \
	done
```

- `tf-test: ## terraform test: plans and applies each module and the environment against a mocked azurerm provide`: Defines the target `tf-test`. Description (shown by `make help`): terraform test: plans and applies each module and the environment against a mocked azurerm provider (no credentials).
- `@set -e; for dir in infra/modules/* $(TF_ENV); do \`: A shell loop over every module folder and the environment. `set -e` makes the shell stop at the first failing command.
- `echo "== terraform test $$dir"; \`: Prints which folder is being tested.
- `(cd $$dir && terraform init -backend=false -input=false >/dev/null && terraform test); \`: In a sub-shell (the parentheses keep the `cd` from affecting the loop): enter the folder, initialize, and run `terraform test`, which runs the `.tftest.hcl` tests against a mocked provider.
- `done`: Ends the shell loop.

**Lines 76 to 77**

```make
scan: ## checkov over infra/ (the skips and their reasons are in .checkov.yaml and inline)
	$(CHECKOV) --config-file .checkov.yaml --quiet --compact
```

- `scan: ## checkov over infra/ (the skips and their reasons are in .checkov.yaml and inline)`: Defines the target `scan`. Description (shown by `make help`): checkov over infra/ (the skips and their reasons are in .checkov.yaml and inline).
- `$(CHECKOV) --config-file .checkov.yaml --quiet --compact`: Runs checkov with this project's configuration; `--quiet` shows only failures and `--compact` omits the code snippets.

**Line 79**

```make
check: lint test validate ## everything that needs no Azure
```

- `check: lint test validate ## everything that needs no Azure`: Defines the target `check`. Its prerequisites: `lint`, `test`, `validate`. Description (shown by `make help`): everything that needs no Azure.

**Lines 81 to 82**

```make
docker-build: ## build the container image
	docker build -t azure-secretless-app:dev .
```

**New idea.** A **container** is a packaged program together with everything it needs, run in isolation from the rest of the machine. An **image** is the read-only package a container starts from, built with a *Dockerfile*. A **registry** stores images so that other machines can pull them.

**New idea.** **Tags** are name/value labels attached to Azure resources. They change no behavior; they record the owner, project and environment and make cost reports and clean-up possible.

- `docker-build: ## build the container image`: Defines the target `docker-build`. Description (shown by `make help`): build the container image.
- `docker build -t azure-secretless-app:dev .`: Builds the container image from the `Dockerfile` in this folder (`.`) and names it (`-t`, tag) `azure-secretless-app:dev`.

**Lines 84 to 85**

```make
docker-smoke: docker-build ## run the image with the in-memory backend and curl it
	scripts/docker-smoke.sh azure-secretless-app:dev
```

**New idea.** **HTTP** is the protocol of the web. A client sends a *request* (a method such as GET or POST, a path, headers and sometimes a body) and the server sends back a *response* with a three-digit **status code**: 200 means success, 201 created, 400 the request was bad, 403 forbidden, 404 not found, 413 too large, 502 a server behind this one failed.

- `docker-smoke: docker-build ## run the image with the in-memory backend and curl it`: Defines the target `docker-smoke`. Its prerequisites: `docker-build`. Description (shown by `make help`): run the image with the in-memory backend and curl it.
- `scripts/docker-smoke.sh azure-secretless-app:dev`: Runs the smoke-test script on the image just built.

**Lines 87 to 88**

```make
up: ## provision the Azure resources (needs az login; billed, see README Deploy)
	scripts/provision.sh
```

- `up: ## provision the Azure resources (needs az login; billed, see README Deploy)`: Defines the target `up`. Description (shown by `make help`): provision the Azure resources (needs az login; billed, see README Deploy).
- `scripts/provision.sh`: Runs the script that creates the Azure resources.

**Lines 90 to 91**

```make
deploy: ## build the image in ACR and roll the container app to it
	scripts/build-and-deploy.sh
```

**New idea.** A **container registry** is a server that stores container images under names and version tags. **Azure Container Registry (ACR)** is Azure's; a service pulls an image from it using an identity that holds the `AcrPull` role.

- `deploy: ## build the image in ACR and roll the container app to it`: Defines the target `deploy`. Description (shown by `make help`): build the image in ACR and roll the container app to it.
- `scripts/build-and-deploy.sh`: Runs the script that builds the image in the registry and adds the app.

**Lines 93 to 94**

```make
smoke: ## health, upload and the role listing against the deployed app
	scripts/smoke.sh
```

- `smoke: ## health, upload and the role listing against the deployed app`: Defines the target `smoke`. Description (shown by `make help`): health, upload and the role listing against the deployed app.
- `scripts/smoke.sh`: Runs the script that calls the deployed app.

**Lines 96 to 97**

```make
audit-config: ## step 4: search the deployed configuration and the source for a key, password or connection string
	scripts/audit-config.sh
```

- `audit-config: ## step 4: search the deployed configuration and the source for a key, password or connection st`: Defines the target `audit-config`. Description (shown by `make help`): step 4: search the deployed configuration and the source for a key, password or connection string.
- `scripts/audit-config.sh`: Runs the script that checks the deployed configuration.

**Lines 99 to 100**

```make
down: ## delete the resource group, purge the vault, remove the budget
	scripts/teardown.sh
```

**New idea.** **Azure Key Vault** stores secrets, keys and certificates behind Azure's access control and writes an audit record of every use. A program reads a secret by calling the vault with its identity, so the secret never has to sit in a file or in the program's settings.

**New idea.** An Azure **budget** watches the spending of a subscription and e-mails people when it passes a threshold such as 80 or 100 percent. It alerts; it does not stop anything from running.

**New idea.** An Azure **resource group** is a folder-like container for the resources of one project. Resources in a group share a life cycle: deleting the group deletes everything in it.

- `down: ## delete the resource group, purge the vault, remove the budget`: Defines the target `down`. Description (shown by `make help`): delete the resource group, purge the vault, remove the budget.
- `scripts/teardown.sh`: Runs the script that deletes everything.

**Lines 102 to 104**

```make
clean:
	rm -rf $(VENV) .pytest_cache .mypy_cache .ruff_cache .import_linter_cache .coverage dist
	find infra -name .terraform -type d -prune -exec rm -rf {} +
```

- `clean:`: Defines the target `clean`.
- `rm -rf $(VENV) .pytest_cache .mypy_cache .ruff_cache .import_linter_cache .coverage dist`: Deletes the environment and every cache and build folder. `-r` recurses into folders and `-f` ignores missing ones.
- `find infra -name .terraform -type d -prune -exec rm -rf {} +`: Finds every folder named `.terraform` under `infra`, does not descend into it (`-prune`) and deletes it (`-exec rm -rf {} +` runs `rm` on all matches).


### Where else this technology appears

Lines of other files that use this technology are explained line by line in the notes of those files. This table lists where to find them.

| File | Matching lines | Explained in |
|---|---|---|
| `.github/workflows/ci.yml` | 28 to 29, 40, 47 | [github-actions.md](github-actions.md) |
| `.editorconfig` | 14 | [editorconfig.md](editorconfig.md) |
| `infra/environments/dev/variables.tf` | 45 | [terraform.md](terraform.md) |
| `infra/modules/storage_uploads/main.tf` | 37 | [azure-storage.md](azure-storage.md) |
| `pyproject.toml` | 61 | [pyproject-toml.md](pyproject-toml.md) |
| `tests/integration/test_azure_live.py` | 3 | [pytest.md](pytest.md) |

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
