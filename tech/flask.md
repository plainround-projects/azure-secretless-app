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

### Every line, in order

This part walks through every file this note is responsible for, from the first non-blank line to the last, in blocks. Each block shows the lines (the numbers say where they sit in the file) and then explains them. New ideas are explained at the first place they are needed; later blocks use them without repeating the explanation.

#### `src/secretless_app/interfaces/http.py`

77 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""The Flask application: three routes and one place that maps named errors to HTTP statuses."""
```

**New idea.** **HTTP** is the protocol of the web. A client sends a *request* (a method such as GET or POST, a path, headers and sometimes a body) and the server sends back a *response* with a three-digit **status code**: 200 means success, 201 created, 400 the request was bad, 403 forbidden, 404 not found, 413 too large, 502 a server behind this one failed.

**New idea.** A **module** is one `.py` file. Python runs a file from the top to the bottom, once, the first time something imports it; `def` and `class` statements at the top level just create functions and classes, they do not run their bodies.

**New idea.** A **docstring** is a text in triple quotes as the very first statement of a module, class or function. It does nothing when the program runs; tools and people read it as the official description.

The module docstring says: The Flask application: three routes and one place that maps named errors to HTTP statuses.

**Lines 3 to 4**

```python
import logging
import time
```

What happens, step by step:

- `logging`: the standard-library module for log records.
- `time`: the standard-library module for clocks and sleeping.

**Lines 6 to 7**

```python
from flask import Flask, Response, jsonify, request
from werkzeug.exceptions import HTTPException, RequestEntityTooLarge
```

**New idea.** **JSON** is a text format for data: objects `{"name": value}`, lists `[1, 2]`, strings, numbers, `true`, `false` and `null`. Most web services send and receive their data as JSON because every programming language can read it.

What happens, step by step:

- `Flask` from `flask`: the web application class.
- `Response` from `flask`: an HTTP response object.
- `jsonify` from `flask`: builds a JSON HTTP response.
- `request` from `flask`: the web request currently being answered.
- `HTTPException` from `werkzeug.exceptions`: the base class for HTTP errors.
- `RequestEntityTooLarge` from `werkzeug.exceptions`: the HTTP 413 error.

**Lines 9 to 10**

```python
from secretless_app.application.services import Services
from secretless_app.domain.errors import AccessDeniedError, DependencyError, InvalidBlobNameError, UploadTooLargeError
```

**New idea.** **Azure Blob Storage** stores files (*blobs*) in a *storage account*. Blobs live in *containers*, which work like top-level folders, and each blob is addressed by account, container and name. (This "container" is not a Docker container.)

What happens, step by step:

- `Services` from the repository's own module `secretless_app.application.services`: Every use case of the app (defined in `src/secretless_app/application/services.py`)
- `AccessDeniedError` from the repository's own module `secretless_app.domain.errors`: The app's identity is known to the service but holds no role that allows the call (defined in `src/secretless_app/domain/errors.py`)
- `DependencyError` from the repository's own module `secretless_app.domain.errors`: An Azure service could not be used; `code` is the service's own error code (defined in `src/secretless_app/domain/errors.py`)
- `InvalidBlobNameError` from the repository's own module `secretless_app.domain.errors`: The requested blob name breaks the naming rule (defined in `src/secretless_app/domain/errors.py`)
- `UploadTooLargeError` from the repository's own module `secretless_app.domain.errors`: The upload is bigger than the configured limit (defined in `src/secretless_app/domain/errors.py`)

**Line 12**

```python
LOGGER = logging.getLogger("secretless_app.http")
```

**New idea.** `logging.getLogger("name")` returns the logger with that name. Code writes records with `.info`, `.warning`, `.error`; handlers decide where the records go and in what format.

What happens, step by step:

- Sets `LOGGER` to the result of calling `logging.getLogger('secretless_app.http')`.

Names used here:

- `logging.getLogger(name)` returns the named logger.

**Lines 15 to 39**

```python
def create_app(services: Services, max_upload_bytes: int) -> Flask:
    """Build the app around `services`; uploads above `max_upload_bytes` are refused before they are read."""
    app = Flask("secretless_app")
    app.config["MAX_CONTENT_LENGTH"] = max_upload_bytes

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

    _register_error_handlers(app)
    _register_request_log(app)
    return app
```

**New idea.** **Azure Key Vault** stores secrets, keys and certificates behind Azure's access control and writes an audit record of every use. A program reads a secret by calling the vault with its identity, so the secret never has to sit in a file or in the program's settings.

**New idea.** A **health check** is a small request that a platform sends to a running program to ask whether it is working. A *liveness* check that keeps failing makes the platform restart the program; a *readiness* check that fails keeps traffic away from it.

The docstring in the code says: Build the app around `services`; uploads above `max_upload_bytes` are refused before they are read.

**Function `create_app`** takes `services` (type `Services`), `max_upload_bytes` (type `int`); gives back `Flask`.

**New idea.** A **type hint** such as `name: str` or `-> int` says what kind of value a parameter or result is. Python does not enforce hints when the program runs; the checker `mypy` reads them before the program runs and reports mismatches.

**New idea.** `def name(parameters):` defines a **function**: a named, reusable block of code. The indented lines under it are its body, which runs only when the function is **called** as `name(values)`. `return value` hands a result back to the caller; a function without `return` gives back `None`.

**New idea.** A **decorator** is a line starting with `@` above a function or class. It passes the function through another function that wraps or registers it. For example `@staticmethod` and `@property` change how a method behaves.

**New idea.** Square brackets after a type, as in `list[str]` or `dict[str, int]`, say what the container holds: a list of text, or a dictionary from text to whole numbers.

**New idea.** A **tuple** `(a, b)` is a fixed list of values. **Unpacking** `x, y = pair` assigns the parts to separate names in one statement.

**New idea.** A **dictionary** `{key: value}` looks values up by key: `d[key]` reads one, `d.get(key)` reads one and returns `None` if missing.

What happens, step by step:

- Sets `app` to the result of calling `Flask('secretless_app')`.
- Sets `app.config['MAX_CONTENT_LENGTH']` to `max_upload_bytes`.
- Defines the inner function `live()`:
  - A text with no effect on the program: a note.
  - Returns `jsonify({'status': 'alive'})`.
- Defines the inner function `health()`:
  - A text with no effect on the program: a note.
  - Sets `report` to the result of calling `services.check_health.run()`.
  - Returns `jsonify({'status': 'ok', 'key_length': report.key_length})`.
- Defines the inner function `upload(name)`:
  - A text with no effect on the program: a note.
  - Sets `saved` to the result of calling `services.save_upload.run(name, request.get_data())`.
  - Returns `(jsonify({'saved': saved.value}), 201)`.
- Calls `_register_error_handlers(app)`.
- Calls `_register_request_log(app)`.
- Returns `app`.

Names used here:

- `Flask(name)` creates the web application object; routes are registered on it.
- `jsonify(data)` builds an HTTP response whose body is the JSON form of `data`.
- `request.get_data()` reads the raw bytes of the request body.

**Lines 42 to 43**

```python
def _register_error_handlers(app: Flask) -> None:
    @app.errorhandler(InvalidBlobNameError)
```

**Function `_register_error_handlers`** takes `app` (type `Flask`); gives back `None`.

**New idea.** `None` is Python's value for "nothing here". Functions that find nothing return it, and a parameter that defaults to `None` means "not given".

The body is split into the parts below.

**Lines 43 to 45**

```python
    @app.errorhandler(InvalidBlobNameError)
    def invalid_name(error: InvalidBlobNameError) -> tuple[Response, int]:
        return jsonify({"error": "invalid_name", "detail": str(error)}), 400
```

**Function `invalid_name`** takes `error` (type `InvalidBlobNameError`); gives back `tuple[Response, int]`.

What happens, step by step:

- Decorator `@app.errorhandler(InvalidBlobNameError)`.
- Returns `(jsonify({'error': 'invalid_name', 'detail': str(error)}), 400)`.

Names used here:

- `@app.errorhandler(SomeError)` registers a function that turns that kind of error into an HTTP response.
- `str(x)` turns a value into text.

**Lines 47 to 49**

```python
    @app.errorhandler(UploadTooLargeError)
    def too_large(error: UploadTooLargeError) -> tuple[Response, int]:
        return jsonify({"error": "upload_too_large", "limit": error.limit}), 413
```

**Function `too_large`** takes `error` (type `UploadTooLargeError`); gives back `tuple[Response, int]`.

What happens, step by step:

- Decorator `@app.errorhandler(UploadTooLargeError)`.
- Returns `(jsonify({'error': 'upload_too_large', 'limit': error.limit}), 413)`.

**Lines 51 to 53**

```python
    @app.errorhandler(RequestEntityTooLarge)
    def body_too_large(error: RequestEntityTooLarge) -> tuple[Response, int]:
        return jsonify({"error": "upload_too_large", "limit": app.config["MAX_CONTENT_LENGTH"]}), 413
```

**Function `body_too_large`** takes `error` (type `RequestEntityTooLarge`); gives back `tuple[Response, int]`.

What happens, step by step:

- Decorator `@app.errorhandler(RequestEntityTooLarge)`.
- Returns `(jsonify({'error': 'upload_too_large', 'limit': app.config['MAX_CONTENT_LENGTH']}), 413)`.

**Lines 55 to 64**

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

**New idea.** **Microsoft Entra ID** (formerly Azure Active Directory) is the identity service of Azure. A **tenant** is one organization's directory in it. Every identity in the directory (a person, a group, an application, a managed identity) has an *object id*, and the party that receives permissions is called the *principal*.

**Function `access_denied`** takes `error` (type `AccessDeniedError`); gives back `tuple[Response, int]`.

**New idea.** Logging calls such as `LOGGER.info("apply %s", name)` take a template with `%s` (text) and `%d` (whole number) placeholders and the values as separate arguments. The logging system only builds the final text if that log level is actually enabled, which is cheaper than an f-string.

What happens, step by step:

- Decorator `@app.errorhandler(AccessDeniedError)`.
- Calls `LOGGER.error` with `'access denied by %s'`; `error.service`; `extra` set to `{'service': error.service, 'code': error.code, 'detail': error.detail}`.
- Returns `(jsonify({'error': 'upstream_access_denied', 'service': error.service, 'code': error.code}), 502)`.

Names used here:

- `LOGGER.error(...)` writes a record at level ERROR (an operation failed).

**Lines 66 to 73**

```python
    @app.errorhandler(DependencyError)
    def dependency_failure(error: DependencyError) -> tuple[Response, int]:
        LOGGER.error(
            "dependency failure in %s",
            error.service,
            extra={"service": error.service, "code": error.code, "detail": error.detail},
        )
        return jsonify({"error": "upstream_failure", "service": error.service, "code": error.code}), 502
```

**Function `dependency_failure`** takes `error` (type `DependencyError`); gives back `tuple[Response, int]`.

What happens, step by step:

- Decorator `@app.errorhandler(DependencyError)`.
- Calls `LOGGER.error` with `'dependency failure in %s'`; `error.service`; `extra` set to `{'service': error.service, 'code': error.code, 'detail': error.detail}`.
- Returns `(jsonify({'error': 'upstream_failure', 'service': error.service, 'code': error.code}), 502)`.

**Lines 75 to 77**

```python
    @app.errorhandler(HTTPException)
    def http_error(error: HTTPException) -> tuple[Response, int]:
        return jsonify({"error": (error.name or "error").lower().replace(" ", "_")}), error.code or 500
```

**Function `http_error`** takes `error` (type `HTTPException`); gives back `tuple[Response, int]`.

**New idea.** `and` is true when both sides are; `or` is true when either is, and it stops at the first true side. `not` flips true and false.

What happens, step by step:

- Decorator `@app.errorhandler(HTTPException)`.
- Returns `(jsonify({'error': (error.name or 'error').lower().replace(' ', '_')}), error.code or 500)`.

Names used here:

- `.replace(old, new)` returns text with every `old` swapped for `new`.
- `.lower()` converts text to lowercase.

**Lines 80 to 97**

```python
def _register_request_log(app: Flask) -> None:
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
        return response
```

**Function `_register_request_log`** takes `app` (type `Flask`); gives back `None`.

**New idea.** **Environment variables** are named text values the operating system hands to every program when it starts (for example `PORT=8080`). `os.environ` is a dictionary-like view of them. They are the usual way to configure a program without changing its code, and the usual way to hand it a setting that differs between machines.

What happens, step by step:

- Defines the inner function `start_timer()`:
  - Sets `request.environ['secretless.started']` to the result of calling `time.perf_counter()`.
- Defines the inner function `log_request(response)`:
  - Sets `started` to the result of calling `request.environ.get('secretless.started', time.perf_counter())`.
  - Calls `LOGGER.info` with `'request'`; `extra` set to `{'method': request.method, 'path': request.path, 'status': response.status_code, 'duration_ms': round((time.p…` (long; see the quote).
  - Returns `response`.

Names used here:

- `LOGGER.info(...)` writes a record at level INFO (normal events).
- `round(x, n)` rounds to `n` decimal places.

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
