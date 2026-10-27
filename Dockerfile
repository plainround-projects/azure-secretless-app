# Two stages: the first installs the hash-pinned dependencies and the package into a virtual environment, the second
# copies only that environment onto a clean base. The base is pinned by version and digest (read on 2026-10-26); update both together.
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
