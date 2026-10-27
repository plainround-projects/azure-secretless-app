# gunicorn

*The production web server that runs the Flask app inside the container. Pinned here: gunicorn 23.0.0.*

## What it is

Gunicorn ("Green Unicorn") is a **WSGI server**: a program that listens on a network port, receives HTTP requests and hands them to a Python web application such as Flask. Flask's own server is only for development; gunicorn is the production-grade server.

## Why this repository uses it

Flask's built-in server is for development. The container and `make run` start the app with gunicorn, which runs several worker processes, replaces a hung worker and finishes in-flight requests when it is asked to stop.

## Where it appears

| File | What it does with it |
|---|---|
| `Dockerfile` | The `CMD` that starts gunicorn with its settings. |
| `Makefile` | `make run` and `make run-denied` start gunicorn on localhost. |
| `src/secretless_app/interfaces/wsgi.py` | The `create()` function gunicorn calls. |
| `tests/e2e/test_server.py` | Starts a real gunicorn process and talks to it over HTTP. |

## How it works underneath

Gunicorn starts a **master** process that starts **worker** processes. Each worker handles requests; `--threads 4` lets a worker handle four at once. If a worker hangs for longer than `--timeout`, the master kills and replaces it.

The argument `"module:create()"` tells gunicorn to import the module and call `create()` to get the application. When the master gets `SIGTERM`, it asks the workers to finish their requests and waits up to `--graceful-timeout` seconds, then exits with code 0. That is a **graceful shutdown**: no request is cut off in the middle.

## Walkthrough of this repository's use

### The container command

```dockerfile
# gunicorn finishes in-flight requests on SIGTERM (graceful timeout 20 s), then exits 0.
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 2 --threads 4 --timeout 30 --graceful-timeout 20 --access-logfile - 'secretless_app.interfaces.wsgi:create()'"]
```

`sh -c "exec gunicorn ..."` runs gunicorn through a shell only so that `${PORT}` can be expanded. `exec` replaces the shell with gunicorn, so gunicorn becomes the container's main process and receives the stop signal. The options: `--bind 0.0.0.0:${PORT}` listens on all network interfaces inside the container; `--workers 2 --threads 4` starts two worker processes with four threads each; `--timeout 30` kills a worker that is silent for 30 seconds; `--graceful-timeout 20` is how long workers get to finish after `SIGTERM`; `--access-logfile -` writes one access line per request to standard output. The last argument, `'secretless_app.interfaces.wsgi:create()'`, means "import this module and call `create()` to get the application".

### The entry point

```python
def create() -> Flask:
    """Read the settings from the environment, wire the adapters and return the app."""
    settings = Settings.from_env(os.environ)
    configure_logging(settings.log_level)
    return create_app(build_services(settings), settings.max_upload_bytes)
```

`create()` reads the settings from the environment, configures logging, wires the adapters and returns the Flask app. If the configuration is wrong, `Settings.from_env` raises an error that lists every problem, and gunicorn exits at start-up instead of serving a broken app.

### Local runs

```make
run: $(STAMP) ## serve the app on localhost with the in-memory backend (no Azure needed); BACKEND=azure uses az login
	BACKEND=$${BACKEND:-memory} $(VENV)/bin/gunicorn --bind 127.0.0.1:$(PORT) "secretless_app.interfaces.wsgi:create()"
```

`BACKEND=${BACKEND:-memory}` sets the backend to `memory` unless you already set another. `make run` therefore serves the app on `127.0.0.1:8000` with the in-memory stand-ins and needs no Azure.

### The end-to-end test

```python
        self.process = subprocess.Popen(
            [
                sys.executable,
                "-m",
                "gunicorn",
                "--bind",
                f"127.0.0.1:{self.port}",
                "--workers",
                "1",
                "secretless_app.interfaces.wsgi:create()",
            ],
            env={**os.environ, "BACKEND": "memory", **env},
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
```

The test starts a real gunicorn on a free port, waits until `/live` answers, sends requests with `urllib`, and at the end sends `SIGTERM` (`process.terminate()`) and checks that the exit code is 0: a graceful shutdown.

## Try it yourself

Check the installed gunicorn.

```bash
.venv/bin/gunicorn --version
```

You should see something like this:

```text
gunicorn (version 23.0.0)
```

Start gunicorn, stop it with SIGTERM and see that it exits cleanly.

```bash
.venv/bin/python -m pytest tests/e2e -q -p no:cacheprovider -k sigterm
```

You should see something like this:

```text
.                                                                        [100%]
1 passed, 3 deselected in 17.10s
```

Ask gunicorn to check that it can load the app.

```bash
BACKEND=memory .venv/bin/gunicorn --check-config 'secretless_app.interfaces.wsgi:create()' && echo config-ok
```

You should see something like this:

```text
config-ok
```

## Mistakes people make

- Running with the default single worker and no timeout settings in a container.
- Binding to `127.0.0.1` inside a container: nothing outside can reach it. The container binds to `0.0.0.0`.
- A shell wrapper that swallows `SIGTERM`; the `CMD` uses `exec` so gunicorn receives it.
- Too many workers on a tiny container.
- Logging secrets in the access log. The access log line holds only method and path.

## Check yourself

1. **What does a WSGI server do?**
   Answer: Listens on a port and passes requests to the Python application.

2. **What does `--graceful-timeout` control?**
   Answer: How long workers have to finish requests after a stop signal.

3. **Why bind to `0.0.0.0` in a container?**
   Answer: `127.0.0.1` is only reachable from inside the container itself.

4. **What does `"module:create()"` mean?**
   Answer: Import the module and call `create()` to get the app.

5. **What happens when a worker exceeds `--timeout`?**
   Answer: The master kills it and starts a new one.

## Further reading

- Gunicorn 23: https://docs.gunicorn.org/en/23.0.0/
- Settings: https://docs.gunicorn.org/en/23.0.0/settings.html
- Signals: https://docs.gunicorn.org/en/23.0.0/signals.html
