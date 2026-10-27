# Flask

*The web framework that turns HTTP requests into calls of the application's use cases. Pinned here: Flask 3.1.3 (with Werkzeug 3.1.9).*

## What it is

Flask is a small **web framework** for Python. A web framework receives HTTP requests, decides which function should answer each one, and turns the function's return value into an HTTP response. Flask follows **WSGI**, the standard way a Python web application and a web server talk to each other.

## Why this repository uses it

The lesson's starting point is a Flask app with two routes. This repository keeps Flask in the outermost layer only (`interfaces/http.py`). The routes call use cases and turn named errors into HTTP answers, so the rules of the app do not depend on the web framework.

## Where it appears

| File | What it does with it |
|---|---|
| `src/secretless_app/interfaces/http.py` | The app factory, the three routes, the error handlers and the request log. |
| `src/secretless_app/interfaces/wsgi.py` | The function gunicorn calls to get the app. |
| `tests/unit/interfaces/test_http.py` | Tests that send requests with `app.test_client()`. |

## How it works underneath

A **route** ties a URL pattern and an HTTP method to a function: `@app.get("/health")`. When a request arrives, Flask matches it, calls the function, and builds a response from what it returns (a dictionary becomes JSON). Parts of the URL in angle brackets, `/upload/<name>`, are passed to the function as arguments.

If a function raises an exception, Flask looks for an **error handler** registered for that exception class (`@app.errorhandler(SomeError)`) and uses its response. `MAX_CONTENT_LENGTH` makes Flask refuse a request whose body is larger than the limit with HTTP 413. `app.test_client()` lets tests send requests to the app in memory, with no server.

`before_request` and `after_request` hooks run around every request; this app uses them to time requests and write one log line per request.

## Walkthrough of this repository's use

### The factory

```python
def create_app(services: Services, max_upload_bytes: int) -> Flask:
    """Build the app around `services`; uploads above `max_upload_bytes` are refused before they are read."""
    app = Flask("secretless_app")
    app.config["MAX_CONTENT_LENGTH"] = max_upload_bytes
```

`create_app` builds a new `Flask` object each time it is called and sets `MAX_CONTENT_LENGTH`. Flask refuses any request whose body is larger than that, with status 413, before the route function runs. The name `"secretless_app"` tells Flask which package the app belongs to.

### The routes

```python
    @app.get("/live")
    def live() -> Response:
        """Liveness: the process answers; touches no dependency, so a missing role never restarts the app."""
        return jsonify({"status": "alive"})

    @app.get("/health")
    def health() -> Response:
        """Read the partner key from the vault and report its length, never the key."""
        report = services.check_health.run()
        return jsonify({"status": "ok", "key_length": report.key_length})

    @app.post("/upload/<name>")
    def upload(name: str) -> tuple[Response, int]:
        """Write the request body to the uploads container under `name`."""
        saved = services.save_upload.run(name, request.get_data())
        return jsonify({"saved": saved.value}), 201
```

`@app.get("/live")` registers the function under it for HTTP GET on that path. `@app.post("/upload/<name>")` does the same for POST and passes the text after `/upload/` into the function as `name`. `jsonify(...)` turns a dictionary into a JSON response with the right content type. A route returns a response, or a response and a status code (`, 201` means "created"). `request.get_data()` reads the request body as bytes.

`/live` touches nothing outside the process, so it answers even when a role has been removed. `/health` reads the secret from the vault and reports only its length. `/upload/<name>` hands the name and the bytes to the `SaveUpload` use case.

### Turning errors into answers

```python
    @app.errorhandler(AccessDeniedError)
    def access_denied(error: AccessDeniedError) -> tuple[Response, int]:
        # The app's identity was refused, not the caller, so this is a bad gateway rather than a 403.
        # The full detail (caller object id, denied action) goes to the log, the code goes to the client.
        LOGGER.error(
            "access denied by %s",
            error.service,
            extra={"service": error.service, "code": error.code, "detail": error.detail},
        )
        return jsonify({"error": "upstream_access_denied", "service": error.service, "code": error.code}), 502
```

`@app.errorhandler(SomeError)` says "when a route raises this error, call this function and use its return value as the response". Here a refused call to a service becomes HTTP **502** (Bad Gateway: a service behind this one refused), not 403: the person calling the app is not forbidden; the app's own identity was refused. The client gets the service and the error code. The full detail (the caller's object id and the denied action) goes to the log through `extra=`, because it is for the operator and not for the client.

### The request log

```python
    @app.before_request
    def start_timer() -> None:
        request.environ["secretless.started"] = time.perf_counter()

    @app.after_request
    def log_request(response: Response) -> Response:
        started = request.environ.get("secretless.started", time.perf_counter())
        LOGGER.info(
            "request",
            extra={
                "method": request.method,
                "path": request.path,
                "status": response.status_code,
                "duration_ms": round((time.perf_counter() - started) * 1000, 1),
            },
        )
```

`before_request` runs before every route, `after_request` after it. The first stores a start time in the request's `environ` dictionary; the second computes the duration and writes one structured log line with the method, path, status and duration in milliseconds.

### How tests use it

```python
def test_health_returns_the_key_length_and_never_the_key(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok", "key_length": len(SECRET_VALUE)}
    assert SECRET_VALUE not in response.get_data(as_text=True)
```

`create_app(services, max_upload_bytes=1024).test_client()` returns an object that sends requests straight into the app in memory. `get_json()` parses the JSON answer. No port is opened and no server runs.

## Try it yourself

Check the installed Flask and Werkzeug versions.

```bash
.venv/bin/pip show flask werkzeug | grep -E '^(Name|Version)'
```

You should see something like this:

```text
Name: Flask
Version: 3.1.3
Name: Werkzeug
Version: 3.1.9
```

Call the real app in memory with the in-memory backend.

```bash
BACKEND=memory .venv/bin/python -c "from secretless_app.infrastructure.settings import Settings; from secretless_app.infrastructure.wiring import build_services; from secretless_app.interfaces.http import create_app; import os; app = create_app(build_services(Settings.from_env({'BACKEND': 'memory'})), 1024); c = app.test_client(); print(c.get('/health').get_json()); print(c.post('/upload/hello.txt', data=b'hi').get_json()); print(c.post('/upload/.bad', data=b'x').status_code)"
```

You should see something like this:

```text
{'key_length': 14, 'status': 'ok'}
{'saved': 'hello.txt'}
400
```

Run the HTTP layer's tests.

```bash
.venv/bin/python -m pytest tests/unit/interfaces -q -p no:cacheprovider
```

You should see something like this:

```text
..........                                                               [100%]
10 passed in 1.66s
```

## Mistakes people make

- Using Flask's built-in development server in production. The container runs gunicorn.
- Returning a secret in a response or log. The health route returns only the length of the key.
- Reading the whole body of an unbounded upload. The size limit is set before the body is read.
- Creating the app at import time with global state. This code builds the app in a factory function, so tests make their own.
- Returning HTML error pages from an API. Every error handler here returns JSON.

## Check yourself

1. **What is a route?**
   Answer: A URL pattern and method tied to a function.

2. **What does an error handler do?**
   Answer: Turns a raised exception of a given class into a response.

3. **What does `MAX_CONTENT_LENGTH` do?**
   Answer: Makes Flask answer 413 to a request body bigger than the limit.

4. **How do tests call the app without a server?**
   Answer: With `app.test_client()`.

5. **Why use an application factory?**
   Answer: So each test, and each server process, builds its own app with its own dependencies.

## Further reading

- Flask 3.1: https://flask.palletsprojects.com/en/stable/
- Error handling: https://flask.palletsprojects.com/en/stable/errorhandling/
- Testing: https://flask.palletsprojects.com/en/stable/testing/
