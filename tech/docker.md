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
