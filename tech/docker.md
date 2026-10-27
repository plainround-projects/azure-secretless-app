# Docker and the Dockerfile

*Packages the app as a small image that runs as a non-root user. Pinned here: Docker Engine 24 (author's machine); base image python:3.13.12-slim-bookworm.*

## What it is

Docker packages a program and everything it needs (the language runtime, libraries, files) into an **image**, and runs the image as a **container**: an isolated process with its own view of the file system. A **Dockerfile** is the text recipe that builds the image, one instruction at a time.

## Why this repository uses it

The deployed app runs in Azure Container Apps, which runs container images. The Dockerfile is also run locally by `make docker-smoke`.

## Where it appears

| File | What it does with it |
|---|---|
| `Dockerfile` | The two-stage build. |
| `.dockerignore` | What is not sent to the build. |
| `scripts/docker-smoke.sh` | Runs and checks the image. |
| `Makefile` | `make docker-build`, `make docker-smoke`. |

## How it works underneath

An image is a stack of read-only **layers**. Each Dockerfile instruction (`RUN`, `COPY`) adds a layer. Docker caches layers: if an instruction and everything above it are unchanged, the layer is reused, which is why files that change rarely (the lock file) are copied before files that change often (the source).

A **multi-stage build** has several `FROM` lines. Early stages can use heavy tools to build; the final stage copies only the results (`COPY --from=build`), so the shipped image stays small. `FROM image@sha256:...` pins the base image by its content hash, so the base cannot change under you.

A container runs one main process (`CMD`). Docker stops it by sending `SIGTERM` and, after a timeout, `SIGKILL`. `USER` sets who the process runs as; running as a non-root user limits the damage of a break-in. `HEALTHCHECK` runs a command from time to time to report whether the container is healthy. A `.dockerignore` file lists what must not be sent to the build.

## Walkthrough of this repository's use

### The build stage

```dockerfile
FROM python:3.13.12-slim-bookworm@sha256:a58daefb915e1e03ad48f3ca4df8832065412c5c35cacb9d39f4229184de12b6 AS build
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_CACHE_DIR=1
WORKDIR /build
RUN python -m venv /opt/venv
COPY requirements.lock ./
RUN /opt/venv/bin/pip install --require-hashes -r requirements.lock
COPY pyproject.toml README.md ./
COPY src ./src
RUN /opt/venv/bin/pip install --no-deps .
```

`FROM image@sha256:... AS build` starts the first stage from the base image pinned by version **and** digest. `ENV PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_CACHE_DIR=1` turns off pip's version check and its download cache so the image stays small. `WORKDIR /build` sets the working folder. `RUN python -m venv /opt/venv` creates a virtual environment. `COPY requirements.lock ./` comes before the source, so the next, slow, step is cached until the lock file changes. `RUN ... pip install --require-hashes -r requirements.lock` installs the pinned dependencies. Then `pyproject.toml`, `README.md` and `src` are copied and `pip install --no-deps .` installs the app itself.

### The final stage

```dockerfile
FROM python:3.13.12-slim-bookworm@sha256:a58daefb915e1e03ad48f3ca4df8832065412c5c35cacb9d39f4229184de12b6 AS build
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_CACHE_DIR=1
WORKDIR /build
RUN python -m venv /opt/venv
COPY requirements.lock ./
RUN /opt/venv/bin/pip install --require-hashes -r requirements.lock
COPY pyproject.toml README.md ./
COPY src ./src
RUN /opt/venv/bin/pip install --no-deps .

FROM python:3.13.12-slim-bookworm@sha256:a58daefb915e1e03ad48f3ca4df8832065412c5c35cacb9d39f4229184de12b6
ENV PATH="/opt/venv/bin:$PATH" PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PORT=8000
RUN useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin app
COPY --from=build /opt/venv /opt/venv
USER 10001
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:%s/live' % os.environ['PORT'], timeout=2)"]
# gunicorn finishes in-flight requests on SIGTERM (graceful timeout 20 s), then exits 0.
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 2 --threads 4 --timeout 30 --graceful-timeout 20 --access-logfile - 'secretless_app.interfaces.wsgi:create()'"]
```

A second `FROM` starts a clean stage; nothing from the first is kept except what is copied. `ENV PATH="/opt/venv/bin:$PATH"` puts the environment's programs first. `PYTHONUNBUFFERED=1` makes logs appear at once; `PYTHONDONTWRITEBYTECODE=1` stops `.pyc` files. `useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin app` creates a user that cannot log in. `COPY --from=build /opt/venv /opt/venv` takes only the installed environment. `USER 10001` switches to that user by number; a numeric id lets a platform verify that the user is not root. `EXPOSE 8000` documents the port. `HEALTHCHECK` runs a small Python one-liner against `/live` every 30 seconds. `CMD [...]` is the command the container runs.

### What is kept out

```text
.git
.venv
.env
.github
.mypy_cache
.pytest_cache
.ruff_cache
.import_linter_cache
.coverage
**/__pycache__
**/.terraform
**/terraform.tfstate*
**/*.tfvars
infra
tests
docs
scripts
```

Git history, the local environment, `.env`, test caches, Terraform files, tests, docs and scripts never enter the build, so the image holds only what the app needs.

### Every line, in order

This part walks through every file this note is responsible for, from the first non-blank line to the last, in blocks. Each block shows the lines (the numbers say where they sit in the file) and then explains them. New ideas are explained at the first place they are needed; later blocks use them without repeating the explanation.

#### `.dockerignore`

17 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 17**

```text
.git
.venv
.env
.github
.mypy_cache
.pytest_cache
.ruff_cache
.import_linter_cache
.coverage
**/__pycache__
**/.terraform
**/terraform.tfstate*
**/*.tfvars
infra
tests
docs
scripts
```

**New idea.** An **environment variable** is a named text value that the operating system hands to every program it starts, such as `PORT=8080`. It is the usual way to configure a program without changing its code, and the way a deployment passes settings that differ between machines.

**New idea.** A **virtual environment** is a private folder holding a copy of the Python interpreter and the libraries installed for one project. It keeps the project's libraries separate from the rest of the machine, so two projects can use different versions of the same library.

**New idea.** A **container** is a packaged program together with everything it needs, run in isolation from the rest of the machine. An **image** is the read-only package a container starts from, built with a *Dockerfile*. A **registry** stores images so that other machines can pull them.

**New idea.** Terraform's **state** is a file in which it records the real resources it created and their ids. Each run compares the code, the state and reality to decide what to change. It may contain sensitive values, so it is never committed; a *backend* is the place where the state is stored.

**New idea.** **Code coverage** measures which lines (and branches) of the program were run while the tests ran. A line the tests never reach is untested, so the project requires a high percentage for its core layers.

**New idea.** **git** is the version-control system that records every change to the project's files as a numbered commit, so any earlier state can be recovered and changes can be reviewed. Files listed in `.gitignore` are never recorded.

- `.git`: A `.dockerignore` file lists what Docker must leave out when it sends the project folder (the **build context**) to the image builder. Leaving things out makes the build faster and keeps secrets and caches out of the image. It uses the same pattern ideas as `.gitignore`. The git history (large, and the image does not need it).
- `.venv`: The local virtual environment.
- `.env`: Local settings that may hold secrets must never be copied into an image.
- `.github`: The CI workflow files.
- `.mypy_cache`: mypy's cache.
- `.pytest_cache`: pytest's cache.
- `.ruff_cache`: ruff's cache.
- `.import_linter_cache`: import-linter's cache.
- `.coverage`: Coverage data.
- `**/__pycache__`: Compiled Python files anywhere in the tree; `**` matches any number of folders.
- `**/.terraform`: Downloaded Terraform plug-ins anywhere in the tree.
- `**/terraform.tfstate*`: Terraform state files anywhere in the tree; they may contain secrets.
- `**/*.tfvars`: Terraform variable files anywhere in the tree; they hold personal ids.
- `infra`: The Terraform code is not needed inside the image.
- `tests`: The tests are not needed inside the image.
- `docs`: The documentation is not needed inside the image.
- `scripts`: The runbook scripts are not needed inside the image.

#### `Dockerfile`

21 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 2**

```dockerfile
# Two stages: the first installs the hash-pinned dependencies and the package into a virtual environment, the second
# copies only that environment onto a clean base. The base is pinned by version and digest (read on 2026-10-26); update both together.
```

**New idea.** A **hash** (or *digest*) is a fixed-length fingerprint calculated from some data. The same data always gives the same hash and any change gives a different one, so comparing hashes shows whether a file or an image is exactly the one that was reviewed.

Comments. A **container image** is a packed, read-only file system plus a start command; a **Dockerfile** is the recipe that builds one, instruction by instruction. This recipe has two *stages*: the first installs the hash-pinned dependencies and the package into a virtual environment; the second copies only that environment onto a clean base, so the final image holds no build tools. The base image is pinned by version *and* by digest, a cryptographic fingerprint of the exact image, so the same bytes are used every time. The two are updated together.

**Line 3**

```dockerfile
FROM python:3.13.12-slim-bookworm@sha256:a58daefb915e1e03ad48f3ca4df8832065412c5c35cacb9d39f4229184de12b6 AS build
```

**New idea.** A **version number** such as `4.81.0` is read as major.minor.patch. A constraint such as `>=4.81` means "4.81 or newer", and Terraform's `~> 4.81` means "4.81 or newer but below 5.0".

`FROM image AS name` starts a stage from a base image. `python:3.13.12-slim-bookworm` is the official Python image, version 3.13.12, in its "slim" variant on Debian 12 ("bookworm"). `@sha256:...` pins the exact image by digest. `AS build` names this stage so a later stage can copy files from it.

**Line 4**

```dockerfile
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_CACHE_DIR=1
```

`ENV` sets environment variables in the image. `PIP_DISABLE_PIP_VERSION_CHECK=1` stops pip from checking the internet for a newer pip, and `PIP_NO_CACHE_DIR=1` stops it from keeping a download cache, which would only make the layer bigger.

**Line 5**

```dockerfile
WORKDIR /build
```

`WORKDIR /build` sets the folder in which the following instructions run (and creates it).

**Line 6**

```dockerfile
RUN python -m venv /opt/venv
```

`RUN python -m venv /opt/venv` runs a command while building: it creates a **virtual environment** (a private Python with its own libraries) in `/opt/venv`. Only this folder will be copied to the final image.

**Line 7**

```dockerfile
COPY requirements.lock ./
```

**New idea.** A **lock file** records the exact versions (and often the hashes) of every package a project uses, including packages that those packages need. Installing from it gives the same result on every machine and on every day.

`COPY requirements.lock ./` copies the lock file from the build context (the project folder, minus what `.dockerignore` excludes) into the current folder of the image. It is copied before the source so that this step is reused from Docker's cache when only the code changes.

**Line 8**

```dockerfile
RUN /opt/venv/bin/pip install --require-hashes -r requirements.lock
```

**New idea.** With **peek-lock**, a receiver takes a message but the broker only hides it under a *lock* for a limited time (30 seconds here). If the receiver *completes* the message it is deleted; if it *abandons* it or the lock expires, the message becomes visible again and is delivered once more, which is why processing must tolerate duplicates.

Installs the locked dependencies. `--require-hashes` makes pip accept only files whose hashes are written in the lock file, so the image contains exactly the reviewed packages.

**Line 9**

```dockerfile
COPY pyproject.toml README.md ./
```

`COPY pyproject.toml README.md ./` copies the package description and the readme that `pyproject.toml` refers to.

**Line 10**

```dockerfile
COPY src ./src
```

`COPY src ./src` copies the source code.

**Line 11**

```dockerfile
RUN /opt/venv/bin/pip install --no-deps .
```

Installs the project itself. `--no-deps` means pip installs only this package; its dependencies are already there from the lock file.

**Line 13**

```dockerfile
FROM python:3.13.12-slim-bookworm@sha256:a58daefb915e1e03ad48f3ca4df8832065412c5c35cacb9d39f4229184de12b6
```

The second stage starts. A new `FROM` begins a fresh image from the same pinned base; nothing of the first stage is present except what is copied explicitly.

**Line 14**

```dockerfile
ENV PATH="/opt/venv/bin:$PATH" PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PORT=8000
```

**New idea.** A **port** is a number between 1 and 65535 that tells the computer which program on it should receive a network connection. An address such as `127.0.0.1:8000` means "this computer, port 8000"; `127.0.0.1` is the address a computer uses to talk to itself.

`ENV` sets: `PATH` with `/opt/venv/bin` in front, so the commands installed there (`gunicorn`) are found; `PYTHONUNBUFFERED=1`, which makes Python write output at once so logs appear immediately; `PYTHONDONTWRITEBYTECODE=1`, which stops it writing compiled `.pyc` files into the image; and `PORT=8000`, the port the web server listens on.

**Line 15**

```dockerfile
RUN useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin app
```

Creates the user the app runs as. `useradd --system` makes a system account, `--uid 10001` fixes its number, `--no-create-home` gives it no home folder and `--shell /usr/sbin/nologin` forbids signing in as it. Running as a normal user instead of `root` limits what a bug or an attacker could do inside the container.

**Line 16**

```dockerfile
COPY --from=build /opt/venv /opt/venv
```

`COPY --from=build /opt/venv /opt/venv` copies the finished virtual environment out of the first stage.

**Line 17**

```dockerfile
USER 10001
```

`USER 10001` makes the following instructions, and the running container, use that account.

**Line 18**

```dockerfile
EXPOSE 8000
```

`EXPOSE 8000` documents the port the container listens on. It does not publish the port by itself.

**Lines 19 to 20**

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:%s/live' % os.environ['PORT'], timeout=2)"]
```

**New idea.** **HTTP** is the protocol of the web. A client sends a *request* (a method such as GET or POST, a path, headers and sometimes a body) and the server sends back a *response* with a three-digit **status code**: 200 means success, 201 created, 400 the request was bad, 403 forbidden, 404 not found, 413 too large, 502 a server behind this one failed.

**New idea.** A **URL** is the full address of something on the web, such as `https://example.com:8443/path?x=1`: the protocol, the host name, an optional port, the path and an optional query.

**New idea.** An **IP address** such as `10.10.2.4` identifies a computer on a network. A **CIDR range** such as `10.10.2.0/24` names a block of addresses: the number after the slash says how many leading bits are fixed, so `/24` fixes the first three numbers and leaves 256 addresses. Ranges starting `10.`, `172.16.` to `172.31.` and `192.168.` are *private*: they are not reachable from the public internet.

**New idea.** A **timeout** is the longest a program waits for something before giving up. Without one, a call to a service that never answers would make the program wait forever.

**New idea.** A **retry** repeats an operation that failed, usually after a pause. It helps with failures that go away by themselves, such as a new permission that takes a few minutes to spread; it must be limited, so a permanent failure is reported and not repeated forever.

**New idea.** A **health check** is a small request that a platform sends to a running program to ask whether it is working. A *liveness* check that keeps failing makes the platform restart the program; a *readiness* check that fails keeps traffic away from it.

`HEALTHCHECK` tells Docker how to test that the container is healthy. Every 30 seconds (`--interval`) it runs the command; the command may take at most 3 seconds (`--timeout`); failures in the first 10 seconds are ignored (`--start-period`); three failures in a row (`--retries`) mark the container unhealthy. The command is a one-line Python program that requests `/live` on the port from the `PORT` variable (`os.environ['PORT']`) and fails if the request fails. The square-bracket form runs the program directly, not through a shell; the trailing backslash continues the instruction on the next line.

**Line 21**

```dockerfile
# gunicorn finishes in-flight requests on SIGTERM (graceful timeout 20 s), then exits 0.
```

**New idea.** A **signal** is a short message the operating system sends to a process. `SIGTERM` asks it to stop politely (a program should finish its current work and exit), `SIGINT` is what Ctrl+C sends, and `SIGKILL` cannot be caught. Container platforms send `SIGTERM` when they stop a container.

**New idea.** A **graceful shutdown** lets a program finish the work it has started, close its connections and exit with code 0 when it is asked to stop, instead of being cut off in the middle of a task.

A comment: on SIGTERM (the signal that asks a program to stop) gunicorn finishes the requests in flight, waits at most 20 seconds, then exits with code 0.

**Line 22**

```dockerfile
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 2 --threads 4 --timeout 30 --graceful-timeout 20 --access-logfile - 'secretless_app.interfaces.wsgi:create()'"]
```

**New idea.** A **process** is one running copy of a program. The operating system gives it its own memory and a number, its *pid*. Two processes do not share variables; they cooperate through files, network connections or signals.

**New idea.** A **thread** is a second line of execution inside one program, running at the same time as the main one. Threads share the program's memory, so data they both touch must be protected, for example with a lock.

**New idea.** Every program has **standard output** (its normal results) and **standard error** (its problem reports), two separate streams. Keeping them apart lets a caller capture the results while still seeing the errors.

`CMD [...]` is the command the container runs when it starts. It uses `sh -c` so that `${PORT}` is expanded, and `exec` replaces the shell with gunicorn, so gunicorn is the main process and receives the stop signal directly. The options: `--bind 0.0.0.0:${PORT}` listens on all network interfaces inside the container; `--workers 2 --threads 4` runs two worker processes with four threads each; `--timeout 30` restarts a worker stuck for 30 seconds; `--graceful-timeout 20` gives workers 20 seconds to finish on shutdown; `--access-logfile -` writes the access log to standard output. The last argument, `secretless_app.interfaces.wsgi:create()`, names the function that builds the web app.


### Where else this technology appears

Lines of other files that use this technology are explained line by line in the notes of those files. This table lists where to find them.

| File | Matching lines | Explained in |
|---|---|---|
| `scripts/docker-smoke.sh` | 4, 7 to 14, 17 to 18, 24 to 25 | [bash.md](bash.md) |
| `Makefile` | 14, 81 to 85 | [make.md](make.md) |
| `scripts/build-and-deploy.sh` | 4, 16, 19 to 20 | [bash.md](bash.md) |
| `scripts/audit-config.sh` | 25 to 26, 29 | [bash.md](bash.md) |
| `.checkov.yaml` | 1, 8 | [checkov.md](checkov.md) |
| `.github/workflows/ci.yml` | 32, 47 | [github-actions.md](github-actions.md) |

## Try it yourself

See the two stages and the pinned base.

```bash
grep -n '^FROM' Dockerfile
```

You should see something like this:

```text
3:FROM python:3.13.12-slim-bookworm@sha256:a58daefb915e1e03ad48f3ca4df8832065412c5c35cacb9d39f4229184de12b6 AS build
13:FROM python:3.13.12-slim-bookworm@sha256:a58daefb915e1e03ad48f3ca4df8832065412c5c35cacb9d39f4229184de12b6
```

Find the lines that decide who runs the container, the port, the health check and the command.

```bash
grep -nE '^(USER|EXPOSE|HEALTHCHECK|CMD)' Dockerfile
```

You should see something like this:

```text
17:USER 10001
18:EXPOSE 8000
19:HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
22:CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 2 --threads 4 --timeout 30 --graceful-timeout 20 --access-logfile - 'secretless_app.interfaces.wsgi:create()'"]
```

Count the ignore rules.

```bash
wc -l .dockerignore
```

You should see something like this:

```text
17 .dockerignore
```

## Mistakes people make

- Running as root. Both images create a user with a fixed numeric id and switch to it.
- Using `latest` or a bare tag as the base. The base here is pinned by version and digest.
- Copying the source before installing dependencies, which defeats layer caching.
- Baking secrets into an image. There are none: the app learns addresses from the environment.
- Shell-form `CMD` without `exec`: the shell receives the stop signal and the app does not. The first image uses `exec gunicorn` for this reason.

## Check yourself

1. **What is the difference between an image and a container?**
   Answer: An image is the packaged recipe result; a container is a running process started from it.

2. **What is a multi-stage build for?**
   Answer: To build with heavy tools in one stage and ship only the result in a small final stage.

3. **Why copy the lock file before the source?**
   Answer: So the slow install layer is reused when only the source changed.

4. **What does `USER 10001` do?**
   Answer: Runs the container's process as a non-root user with that numeric id.

5. **What signal asks a container to stop?**
   Answer: `SIGTERM`, followed by `SIGKILL` after a timeout.

## Further reading

- Dockerfile reference: https://docs.docker.com/reference/dockerfile/
- Multi-stage builds: https://docs.docker.com/build/building/multi-stage/
- Docker Engine 24 is the version on the author's machine.
