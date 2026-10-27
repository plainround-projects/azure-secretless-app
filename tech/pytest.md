# pytest and coverage

*Runs the tests and measures how much code they run. Pinned here: pytest 9.1.1, pytest-cov 7.1.0, coverage 7.17.0.*

## What it is

pytest is a tool that finds and runs the tests of a Python project. A **test** is a function whose name starts with `test_`. It runs some code and uses `assert` to say what must be true. If an `assert` is false, pytest reports a failure and shows both sides of the comparison. **Coverage** (the `pytest-cov` plugin, which uses the `coverage` library) measures which lines of the code the tests ran.

## Why this repository uses it

The lesson's app has no automated tests in its starting point. This repository adds tests at three levels so the behavior can be checked without Azure: unit tests with in-memory fakes, an end-to-end test that starts the real server, and a live test that is skipped unless you have a subscription.

## Where it appears

| File | What it does with it |
|---|---|
| `tests/unit/` | Unit tests, one folder per layer. |
| `tests/e2e/test_server.py` | Starts the real gunicorn and sends requests. |
| `tests/integration/test_azure_live.py` | The live Azure test, skipped by default. |
| `tests/conftest.py` | Shared fixtures. |
| `pyproject.toml` | pytest and coverage settings. |
| `Makefile` | `make test` runs pytest with coverage and checks the 95 percent bar. |

## How it works underneath

pytest walks the folders named in `testpaths`, imports every file called `test_*.py` and collects the functions called `test_*`. For each one it runs the function. A test that raises an exception, or fails an `assert`, is a failure; a test that finishes is a pass.

A **fixture** is a function marked `@pytest.fixture`. When a test lists the fixture's name as a parameter, pytest calls the fixture first and passes in the result. That is how tests get a fresh temporary file or a fake object without repeating code.

A **marker** (`@pytest.mark.something`) labels tests so you can choose them (`-m e2e`). `--strict-markers` makes an unknown label an error, which catches typos.

With `--cov=package`, coverage watches the program while the tests run, records every line and branch that executed, and prints a table of what was missed.

## Walkthrough of this repository's use

### The settings

```toml
[tool.pytest.ini_options]
```

```toml
[tool.coverage.run]
source = ["secretless_app"]
branch = true

[tool.coverage.report]
show_missing = true
skip_covered = false
```

`testpaths` is where pytest looks. `addopts = "-ra --strict-markers"` adds options to every run: `-ra` prints a summary of every skipped or failed test, `--strict-markers` rejects unknown markers. `markers` declares `azure` and `e2e` with a description. `branch = true` makes coverage count both outcomes of every `if`, not only whether the line ran. `show_missing` prints the line numbers that were not run.

### A fixture

```python
@pytest.fixture
def blobs() -> InMemoryBlobStore:
    return InMemoryBlobStore()


@pytest.fixture
def services(blobs: InMemoryBlobStore) -> Services:
    secrets = InMemorySecretStore({SECRET_NAME: SECRET_VALUE})
    return Services(CheckHealth(secrets, SECRET_NAME), SaveUpload(blobs, max_bytes=1024))
```

The `blobs` fixture returns a fresh in-memory blob store for each test. The `services` fixture asks for `blobs`, so pytest builds `blobs` first, and builds `Services` around it with the in-memory secret store. Test functions declare `services` or `blobs` as parameters and receive them.

### A test that reads like a sentence

```python
def test_an_upload_at_the_limit_is_accepted_and_one_byte_over_is_refused():
    use_case = SaveUpload(InMemoryBlobStore(), max_bytes=4)
    use_case.run("ok.bin", b"1234")
    with pytest.raises(UploadTooLargeError):
        use_case.run("big.bin", b"12345")
```

The test name says the behavior. `with pytest.raises(UploadTooLargeError):` passes only if the block raises that error.

### A parametrized test

```python
@pytest.mark.parametrize("value", ["hello.txt", "a", "Report_2026-10.csv", "x" * 128, "v1.2.3.tar.gz"])
def test_a_plain_file_name_is_accepted(value):
    assert BlobName(value).value == value
```

`parametrize` runs one test function once per listed value, each reported separately. Eleven bad names become eleven checks.

### The end-to-end marker

```python
pytestmark = pytest.mark.e2e
```

`pytestmark` applies the `e2e` marker to every test in the file, so `make test-e2e` can select them with `-m e2e`.

### The coverage bar

```make
test: $(STAMP) ## unit and end-to-end tests with coverage (no Azure needed)
	$(PY) -m pytest tests/unit tests/e2e --cov=secretless_app --cov-report=term
	$(PY) -m coverage report --include='src/secretless_app/domain/*,src/secretless_app/application/*' --fail-under=95
```

`--cov=secretless_app` measures the package. The second command reports only the `domain` and `application` folders and fails if they are below 95 percent. Those layers hold the rules, so they carry the bar; they are at 100 percent.

### Every line, in order

This part walks through every file this note is responsible for, from the first non-blank line to the last, in blocks. Each block shows the lines (the numbers say where they sit in the file) and then explains them. New ideas are explained at the first place they are needed; later blocks use them without repeating the explanation.

#### `tests/conftest.py`

15 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""Shared fixtures."""
```

**New idea.** A **module** is one `.py` file. Python runs a file from the top to the bottom, once, the first time something imports it; `def` and `class` statements at the top level just create functions and classes, they do not run their bodies.

**New idea.** A **docstring** is a text in triple quotes as the very first statement of a module, class or function. It does nothing when the program runs; tools and people read it as the official description.

The module docstring says: Shared fixtures.

**Line 3**

```python
import pytest
```

What happens, step by step:

- `pytest`: the test framework.

**Lines 5 to 8**

```python
from secretless_app.application.check_health import CheckHealth
from secretless_app.application.save_upload import SaveUpload
from secretless_app.application.services import Services
from secretless_app.infrastructure.memory_adapters import InMemoryBlobStore, InMemorySecretStore
```

**New idea.** **Azure role-based access control (RBAC)** decides who may do what. A *role* is a named bundle of permissions (for example "Key Vault Secrets User" may read secrets), a *scope* is where the grant applies (one resource, a resource group, a whole subscription), and a *role assignment* connects an identity, a role and a scope. The smaller the scope, the less a leaked identity can do.

**New idea.** **Azure Blob Storage** stores files (*blobs*) in a *storage account*. Blobs live in *containers*, which work like top-level folders, and each blob is addressed by account, container and name. (This "container" is not a Docker container.)

What happens, step by step:

- `CheckHealth` from the repository's own module `secretless_app.application.check_health`: Read the partner key and report its length (defined in `src/secretless_app/application/check_health.py`)
- `SaveUpload` from the repository's own module `secretless_app.application.save_upload`: Validate the name and the size, then write the blob (overwriting a blob of the same name) (defined in `src/secretless_app/application/save_upload.py`)
- `Services` from the repository's own module `secretless_app.application.services`: Every use case of the app (defined in `src/secretless_app/application/services.py`)
- `InMemoryBlobStore` from the repository's own module `secretless_app.infrastructure.memory_adapters`: A dictionary of blobs that can pretend the Blob Data Contributor role was removed (defined in `src/secretless_app/infrastructure/memory_adapters.py`)
- `InMemorySecretStore` from the repository's own module `secretless_app.infrastructure.memory_adapters`: A dictionary of secrets that can pretend the Secrets User role was removed (defined in `src/secretless_app/infrastructure/memory_adapters.py`)

**Lines 10 to 11**

```python
SECRET_NAME = "partner-api-key"
SECRET_VALUE = "demo-value-123"
```

What happens, step by step:

- Sets `SECRET_NAME` to `'partner-api-key'`.
- Sets `SECRET_VALUE` to `'demo-value-123'`.

**Lines 14 to 16**

```python
@pytest.fixture
def blobs() -> InMemoryBlobStore:
    return InMemoryBlobStore()
```

**Function `blobs`** takes no parameters; gives back `InMemoryBlobStore`.

**New idea.** A **type hint** such as `name: str` or `-> int` says what kind of value a parameter or result is. Python does not enforce hints when the program runs; the checker `mypy` reads them before the program runs and reports mismatches.

**New idea.** A **fixture** is a helper function marked `@pytest.fixture`. When a test lists the fixture's name as a parameter, pytest runs the fixture first and passes in what it returns. A fixture with `yield` hands the value to the test, then runs the code after the `yield` as clean-up once the test ends.

**New idea.** `def name(parameters):` defines a **function**: a named, reusable block of code. The indented lines under it are its body, which runs only when the function is **called** as `name(values)`. `return value` hands a result back to the caller; a function without `return` gives back `None`.

What happens, step by step:

- Decorator `@pytest.fixture`.
- Returns `InMemoryBlobStore()`.

**Lines 19 to 22**

```python
@pytest.fixture
def services(blobs: InMemoryBlobStore) -> Services:
    secrets = InMemorySecretStore({SECRET_NAME: SECRET_VALUE})
    return Services(CheckHealth(secrets, SECRET_NAME), SaveUpload(blobs, max_bytes=1024))
```

**Function `services`** takes `blobs` (type `InMemoryBlobStore`); gives back `Services`.

**New idea.** A **dictionary** `{key: value}` looks values up by key: `d[key]` reads one, `d.get(key)` reads one and returns `None` if missing.

What happens, step by step:

- Decorator `@pytest.fixture`.
- Sets `secrets` to the result of calling `InMemorySecretStore({SECRET_NAME: SECRET_VALUE})`.
- Returns `Services(CheckHealth(secrets, SECRET_NAME), SaveUpload(blobs, max_bytes=1024))`.

#### `tests/e2e/test_server.py`

87 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""Start the real gunicorn server with the in-memory backend and drive it over HTTP."""
```

**New idea.** **HTTP** is the protocol of the web. A client sends a *request* (a method such as GET or POST, a path, headers and sometimes a body) and the server sends back a *response* with a three-digit **status code**: 200 means success, 201 created, 400 the request was bad, 403 forbidden, 404 not found, 413 too large, 502 a server behind this one failed.

**New idea.** Terraform's **state** is a file in which it records the real resources it created and their ids. Each run compares the code, the state and reality to decide what to change. It may contain sensitive values, so it is never committed; a *backend* is the place where the state is stored.

The module docstring says: Start the real gunicorn server with the in-memory backend and drive it over HTTP.

**Lines 3 to 12**

```python
import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from collections.abc import Iterator
from contextlib import closing
```

What happens, step by step:

- `json`: the standard-library module for JSON.
- `os`: the standard-library module for the operating system (environment variables, files).
- `socket`: the standard-library module for network connections and name lookup.
- `subprocess`: the standard-library module for starting other programs.
- `sys`: the standard-library module for the running interpreter (arguments, exit, streams).
- `time`: the standard-library module for clocks and sleeping.
- `urllib.error`: the standard-library module of HTTP error classes.
- `urllib.request`: the standard-library module for sending HTTP requests.
- `Iterator` from `collections.abc`: the type hint for an object handing out items one at a time.
- `closing` from `contextlib`: wraps an object so a `with` block calls its `close()` at the end.

**Line 14**

```python
import pytest
```

What happens, step by step:

- `pytest`: the test framework.

**Line 16**

```python
pytestmark = pytest.mark.e2e
```

What happens, step by step:

- Sets `pytestmark` to `pytest.mark.e2e`.

**Lines 19 to 22**

```python
def _free_port() -> int:
    with closing(socket.socket()) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])
```

**New idea.** An **IP address** such as `10.10.2.4` identifies a computer on a network. A **CIDR range** such as `10.10.2.0/24` names a block of addresses: the number after the slash says how many leading bits are fixed, so `/24` fixes the first three numbers and leaves 256 addresses. Ranges starting `10.`, `172.16.` to `172.31.` and `192.168.` are *private*: they are not reachable from the public internet.

**New idea.** A **version number** such as `4.81.0` is read as major.minor.patch. A constraint such as `>=4.81` means "4.81 or newer", and Terraform's `~> 4.81` means "4.81 or newer but below 5.0".

**Function `_free_port`** takes no parameters; gives back `int`.

**New idea.** A `with` block uses a **context manager**: an object that does set-up when the block starts and clean-up when it ends, even if an error happens in between (for example, closing a file or releasing a lock). `with x as y:` runs the block with the set-up result in `y`.

**New idea.** A **tuple** `(a, b)` is a fixed list of values. **Unpacking** `x, y = pair` assigns the parts to separate names in one statement.

What happens, step by step:

- Inside a block that `closing(socket.socket())` and call it `sock`:
  - Calls `sock.bind(('127.0.0.1', 0))`.
  - Returns `int(sock.getsockname()[1])`.

Names used here:

- `int(x)` turns a value into a whole number.

**Line 25**

```python
class Server:
```

**Class `Server`**.

**New idea.** `class Name:` defines a **class**: a blueprint for objects that bundle data (attributes) with functions that work on it (methods). Calling the class, `Name(...)`, builds one object, an **instance**.

**Lines 26 to 52**

```python
    def __init__(self, **env: str) -> None:
        self.port = _free_port()
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
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            try:
                self.request("GET", "/live")
                return
            except (urllib.error.URLError, ConnectionError, TimeoutError):
                time.sleep(0.1)
        self.process.kill()
        raise RuntimeError("server did not start")
```

**New idea.** A **port** is a number between 1 and 65535 that tells the computer which program on it should receive a network connection. An address such as `127.0.0.1:8000` means "this computer, port 8000"; `127.0.0.1` is the address a computer uses to talk to itself.

**New idea.** Every program has **standard output** (its normal results) and **standard error** (its problem reports), two separate streams. Keeping them apart lets a caller capture the results while still seeing the errors.

**New idea.** A **health check** is a small request that a platform sends to a running program to ask whether it is working. A *liveness* check that keeps failing makes the platform restart the program; a *readiness* check that fails keeps traffic away from it.

**Method `__init__`** takes `**env` (all extra named values); gives back `None`.

**New idea.** `*args` collects extra positional arguments into a tuple, and `**kwargs` collects extra named arguments into a dictionary.

**New idea.** Inside a method, the first parameter, by convention `self`, is the object the method was called on. `self.value` reads or sets an attribute of that object.

**New idea.** `__init__` is the special method Python calls right after it creates an object; it sets the object's starting attributes. Names with double underscores on both sides are **dunder methods**: Python calls them for you in response to syntax (`__init__` on creation, `__repr__` when printing, `__len__` for `len(x)`, `__eq__` for `==`).

**New idea.** `while condition:` repeats its block as long as the condition stays true. `break` leaves the loop at once; `continue` jumps to the next round.

**New idea.** `raise Error(...)` stops the current function and signals a failure. `raise NewError(...) from error` also records the original error as the cause, so the traceback shows both.

**New idea.** `None` is Python's value for "nothing here". Functions that find nothing return it, and a parameter that defaults to `None` means "not given".

**New idea.** `subprocess.run([...])` starts another program as a separate **process** (a running program with its own memory) and waits for it; the result holds its exit code and output.

**New idea.** `try:` runs code that might fail. `except SomeError:` runs only if that kind of error is raised inside the `try`; the program continues after the `except` block instead of stopping. `finally:` runs always, error or not, and is used for clean-up.

**New idea.** An **f-string** is text written `f"...{value}..."`: whatever is inside the braces is evaluated and its text is put into the string. A format after a colon controls how: `{x:g}` prints a number without trailing zeros, `{x:.1f}` keeps one decimal, `{x!r}` uses the value's `repr`.

**New idea.** **Environment variables** are named text values the operating system hands to every program when it starts (for example `PORT=8080`). `os.environ` is a dictionary-like view of them. They are the usual way to configure a program without changing its code, and the usual way to hand it a setting that differs between machines.

What happens, step by step:

- Sets `self.port` to the result of calling `_free_port()`.
- Sets `self.process` to the result of calling `subprocess.Popen` with `[sys.executable, '-m', 'gunicorn', '--bind', f'127.0.0.1:{self.port}', '--workers', '1', 'secretless_app.inte…` (long; see the quote); `env` set to `{**os.environ, 'BACKEND': 'memory', **env}`; `stdout` set to `subprocess.PIPE`; `stderr` set to `subprocess.STDOUT`; `text` set to `True`.
- Sets `deadline` to `time.monotonic() + 90`.
- While `time.monotonic()` is less than `deadline`:
  - Try:
    - Calls `self.request('GET', '/live')`.
    - Returns nothing (`None`).
  - If `(urllib.error.URLError, ConnectionError, TimeoutError)` is raised:
    - Calls `time.sleep(0.1)`.
- Calls `self.process.kill()`.
- Raises `RuntimeError('server did not start')`.

Names used here:

- `time.monotonic()` is a clock that only moves forward; it is right for measuring durations (it ignores changes of the wall clock).
- `time.sleep(s)` pauses the program for `s` seconds.
- `RuntimeError` is the general error for a failure that fits no other class.

**Lines 54 to 60**

```python
    def request(self, method: str, path: str, body: bytes | None = None) -> tuple[int, dict[str, object]]:
        request = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", data=body, method=method)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as error:
            return error.code, json.load(error)
```

**New idea.** A **URL** is the full address of something on the web, such as `https://example.com:8443/path?x=1`: the protocol, the host name, an optional port, the path and an optional query.

**New idea.** A **timeout** is the longest a program waits for something before giving up. Without one, a call to a service that never answers would make the program wait forever.

**Method `request`** takes `method` (type `str`), `path` (type `str`), `body` (type `bytes | None`), default `None`; gives back `tuple[int, dict[str, object]]`.

**New idea.** A parameter written `name=value` has a **default**: if the caller leaves it out, the default is used.

**New idea.** Square brackets after a type, as in `list[str]` or `dict[str, int]`, say what the container holds: a list of text, or a dictionary from text to whole numbers.

**New idea.** `A | B` in a type hint means "either an A or a B". `str | None` means "text, or nothing at all".

**New idea.** **JSON** is a text format for data: objects `{"key": value}`, arrays `[1, 2]`, strings, numbers, `true`, `false` and `null`. `json.dumps(x)` turns Python data into JSON text and `json.loads(text)` turns JSON text back into Python data.

What happens, step by step:

- Sets `request` to the result of calling `urllib.request.Request(f'http://127.0.0.1:{self.port}{path}', data=body, method=method)`.
- Try:
  - Inside a block that `urllib.request.urlopen(request, timeout=30)` and call it `response`:
    - Returns `(response.status, json.load(response))`.
- If `urllib.error.HTTPError` is raised (the error is called `error`):
  - Returns `(error.code, json.load(error))`.

Names used here:

- `urllib.request.Request(url, headers=...)` describes an HTTP request.
- `urllib.request.urlopen(request)` sends an HTTP request using only the standard library.
- `json.load(file)` reads JSON from an open file.

**Lines 62 to 65**

```python
    def stop(self) -> str:
        self.process.terminate()  # gunicorn finishes in-flight requests on SIGTERM
        output, _ = self.process.communicate(timeout=120)
        return output
```

**New idea.** A **signal** is a short message the operating system sends to a process. `SIGTERM` asks it to stop politely (a program should finish its current work and exit), `SIGINT` is what Ctrl+C sends, and `SIGKILL` cannot be caught. Container platforms send `SIGTERM` when they stop a container.

**Method `stop`** takes no parameters; gives back `str`.

What happens, step by step:

- Calls `self.process.terminate()`.
- Sets `(output, _)` to the result of calling `self.process.communicate(timeout=120)`.
- Returns `output`.

**Lines 68 to 72**

```python
@pytest.fixture
def server() -> Iterator[Server]:
    instance = Server()
    yield instance
    instance.stop()
```

**Function `server`** takes no parameters; gives back `Iterator[Server]`.

**New idea.** `yield value` makes a function a **generator**: instead of returning once, it hands out one value at a time and pauses until the next one is asked for.

What happens, step by step:

- Decorator `@pytest.fixture`.
- Sets `instance` to the result of calling `Server()`.
- Evaluates `(yield instance)`.
- Calls `instance.stop()`.

**Lines 75 to 77**

```python
def test_the_lessons_curl_session_works_end_to_end(server):
    assert server.request("GET", "/health") == (200, {"status": "ok", "key_length": 14})
    assert server.request("POST", "/upload/hello.txt", b"hello") == (201, {"saved": "hello.txt"})
```

**Function `test_the_lessons_curl_session_works_end_to_end`** takes `server`.

**New idea.** A **test function** is a function whose name starts with `test_`. pytest finds it by that name, calls it, and reports a pass if it returns normally and a failure if an `assert` fails or an error is raised.

**New idea.** `assert condition` checks that a condition is true. If it is false, the program stops with an `AssertionError`. Test code uses it to state expectations; pytest shows both sides of a failed comparison.

**New idea.** `bytes` is raw binary data (`b"..."`), as opposed to `str`, which is text. `text.encode("utf-8")` turns text into bytes and `data.decode("utf-8")` turns bytes back into text.

What happens, step by step:

- Checks that `server.request('GET', '/health')` equals `(200, {'status': 'ok', 'key_length': 14})`.
- Checks that `server.request('POST', '/upload/hello.txt', b'hello')` equals `(201, {'saved': 'hello.txt'})`.

**Lines 80 to 87**

```python
def test_removing_the_blob_role_is_refused_and_the_log_names_the_code():
    denied = Server(MEMORY_DENY="blob")
    status, body = denied.request("POST", "/upload/hello.txt", b"hello")
    output = denied.stop()
    assert status == 502
    assert body["code"] == "AuthorizationPermissionMismatch"
    log_lines = [json.loads(line) for line in output.splitlines() if line.startswith("{")]
    assert any(line.get("code") == "AuthorizationPermissionMismatch" and line["level"] == "ERROR" for line in log_lines)
```

**Function `test_removing_the_blob_role_is_refused_and_the_log_names_the_code`** takes no parameters.

**New idea.** A **comprehension** builds a list, set or dictionary in one expression: `[f(x) for x in things if keep(x)]` means "for each `x` in `things` that passes `keep`, take `f(x)`". With braces and `key: value` it builds a dictionary.

**New idea.** A **generator expression** `(f(x) for x in things)` produces its values one at a time as they are asked for, instead of building the whole list first.

**New idea.** `and` is true when both sides are; `or` is true when either is, and it stops at the first true side. `not` flips true and false.

What happens, step by step:

- Sets `denied` to the result of calling `Server(MEMORY_DENY='blob')`.
- Sets `(status, body)` to the result of calling `denied.request('POST', '/upload/hello.txt', b'hello')`.
- Sets `output` to the result of calling `denied.stop()`.
- Checks that `status` equals `502`.
- Checks that `body['code']` equals `'AuthorizationPermissionMismatch'`.
- Sets `log_lines` to `[json.loads(line) for line in output.splitlines() if line.startswith('{')]`.
- Checks that `any((line.get('code') == 'AuthorizationPermissionMismatch' and line['level'] == 'ERROR' for line in log_lines…` (long; see the quote) is true.

Names used here:

- `json.loads(text)` turns JSON text into Python data.
- `.splitlines()` cuts text into its lines.
- `.startswith(prefix)` is true when the text begins with `prefix`.
- `any(x)` is true if at least one item is true.

**Lines 90 to 93**

```python
def test_a_sigterm_stops_the_server_cleanly(server):
    server.request("GET", "/live")
    server.process.terminate()
    assert server.process.wait(timeout=120) == 0
```

**Function `test_a_sigterm_stops_the_server_cleanly`** takes `server`.

What happens, step by step:

- Calls `server.request('GET', '/live')`.
- Calls `server.process.terminate()`.
- Checks that `server.process.wait(timeout=120)` equals `0`.

**Lines 96 to 106**

```python
def test_bad_configuration_stops_the_start_up_with_every_problem_named():
    process = subprocess.run(
        [sys.executable, "-m", "gunicorn", "--bind", "127.0.0.1:0", "secretless_app.interfaces.wsgi:create()"],
        env={**os.environ, "BACKEND": "azure", "VAULT_URL": "", "STORAGE_URL": ""},
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    assert process.returncode != 0
    assert "VAULT_URL" in process.stdout + process.stderr
```

**Function `test_bad_configuration_stops_the_start_up_with_every_problem_named`** takes no parameters.

**New idea.** `a in b` is true when `a` is one of the items of `b` (or a piece of the text `b`).

What happens, step by step:

- Sets `process` to the result of calling `subprocess.run` with `[sys.executable, '-m', 'gunicorn', '--bind', '127.0.0.1:0', 'secretless_app.interfaces.wsgi:create()']`; `env` set to `{**os.environ, 'BACKEND': 'azure', 'VAULT_URL': '', 'STORAGE_URL': ''}`; `capture_output` set to `True`; `text` set to `True`; `timeout` set to `120`; `check` set to `False`.
- Checks that `process.returncode` does not equal `0`.
- Checks that `'VAULT_URL'` is one of / is inside `process.stdout + process.stderr`.

#### `tests/integration/test_azure_live.py`

25 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 4**

```python
"""The real adapters against the deployed resources. Skipped unless RUN_AZURE_TESTS=1 and you are signed in.

Run it after `make deploy`, with the three addresses exported (see docs/RUNBOOK.md): `make test-azure`.
"""
```

The module docstring says: The real adapters against the deployed resources. Skipped unless RUN_AZURE_TESTS=1 and you are signed in. Run it after `make deploy`, with the three addresses exported (see docs/RUNBOOK.md): `make test-azure`.

**Lines 6 to 7**

```python
import os
import uuid
```

**New idea.** A **GUID** (or UUID) is a 128-bit identifier written as 32 hexadecimal digits in groups, such as `00000000-0000-0000-0000-000000000000`. Azure uses them for subscriptions, tenants and identities. The all-zero value in examples is a placeholder, not a real id.

What happens, step by step:

- `os`: the standard-library module for the operating system (environment variables, files).
- `uuid`: the standard-library module for unique identifiers.

**Line 9**

```python
import pytest
```

What happens, step by step:

- `pytest`: the test framework.

**Lines 11 to 13**

```python
from secretless_app.domain.blob_name import BlobName
from secretless_app.infrastructure.azure_adapters import BlobUploads, KeyVaultSecretStore, build_credential
from secretless_app.infrastructure.settings import Settings
```

**New idea.** A **managed identity** is an identity that Azure creates and looks after for a workload, with no password to store or rotate. When the workload runs, it asks a local Azure endpoint for a token for that identity. A *user-assigned* identity exists on its own and can be attached to several resources; its *client id* names it when a program asks for a token and its *principal id* names it when roles are granted.

**New idea.** **Azure Key Vault** stores secrets, keys and certificates behind Azure's access control and writes an audit record of every use. A program reads a secret by calling the vault with its identity, so the secret never has to sit in a file or in the program's settings.

What happens, step by step:

- `BlobName` from the repository's own module `secretless_app.domain.blob_name`: A blob name that is safe to use as a path segment: 1 to 128 characters, no slash, no dot-dot (defined in `src/secretless_app/domain/blob_name.py`)
- `BlobUploads` from the repository's own module `secretless_app.infrastructure.azure_adapters`: Writes blobs with the Storage Blob Data Contributor role on one container (defined in `src/secretless_app/infrastructure/azure_adapters.py`)
- `KeyVaultSecretStore` from the repository's own module `secretless_app.infrastructure.azure_adapters`: Reads secrets with the Key Vault Secrets User role (defined in `src/secretless_app/infrastructure/azure_adapters.py`)
- `build_credential` from the repository's own module `secretless_app.infrastructure.azure_adapters`: In Azure the managed identity named by `client_id` answers; on a laptop `az login` does (defined in `src/secretless_app/infrastructure/azure_adapters.py`)
- `Settings` from the repository's own module `secretless_app.infrastructure.settings`: Everything the app reads from the environment (defined in `src/secretless_app/infrastructure/settings.py`)

**Lines 15 to 18**

```python
pytestmark = [
    pytest.mark.azure,
    pytest.mark.skipif(os.environ.get("RUN_AZURE_TESTS") != "1", reason="set RUN_AZURE_TESTS=1 after deploying"),
]
```

What happens, step by step:

- Sets `pytestmark` to `[pytest.mark.azure, pytest.mark.skipif(os.environ.get('RUN_AZURE_TESTS') != '1', reason='set RUN_AZURE_TESTS=…` (long; see the quote).

**Lines 21 to 23**

```python
@pytest.fixture(scope="module")
def settings() -> Settings:
    return Settings.from_env(os.environ)
```

**Function `settings`** takes no parameters; gives back `Settings`.

What happens, step by step:

- Decorator `@pytest.fixture(scope='module')`.
- Returns `Settings.from_env(os.environ)`.

Names used here:

- `from_env` is the repository's own: Read and validate `env`; raise `ConfigError` naming every problem at once (defined in `src/secretless_app/infrastructure/settings.py`)

**Lines 26 to 29**

```python
def test_the_signed_in_identity_can_read_the_partner_key(settings):
    credential = build_credential(settings.client_id)
    secret = KeyVaultSecretStore(settings.vault_url or "", credential).get(settings.secret_name)
    assert len(secret) > 0
```

**Function `test_the_signed_in_identity_can_read_the_partner_key`** takes `settings`.

What happens, step by step:

- Sets `credential` to the result of calling `build_credential(settings.client_id)`.
- Sets `secret` to the result of calling `KeyVaultSecretStore(settings.vault_url or '', credential).get(settings.secret_name)`.
- Checks that `len(secret)` is greater than `0`.

Names used here:

- `len(x)` counts the items in `x`.

**Lines 32 to 36**

```python
def test_the_signed_in_identity_can_write_a_blob(settings):
    credential = build_credential(settings.client_id)
    BlobUploads(settings.storage_url or "", settings.container, credential).put(
        BlobName(f"live-test-{uuid.uuid4().hex[:8]}.txt"), b"written by the live test"
    )
```

**Function `test_the_signed_in_identity_can_write_a_blob`** takes `settings`.

**New idea.** `items[1:3]` is a **slice**: the elements from position 1 up to (not including) 3. Positions start at 0, and a negative position counts from the end.

What happens, step by step:

- Sets `credential` to the result of calling `build_credential(settings.client_id)`.
- Calls `BlobUploads(settings.storage_url or '', settings.container, credential).put` with `BlobName(f'live-test-{uuid.uuid4().hex[:8]}.txt')`; `b'written by the live test'`.

Names used here:

- `uuid.uuid4()` creates a random unique identifier.

#### `tests/unit/application/test_use_cases.py`

45 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
import pytest
```

What happens, step by step:

- `pytest`: the test framework.

**Lines 3 to 7**

```python
from secretless_app.application.check_health import CheckHealth
from secretless_app.application.save_upload import SaveUpload
from secretless_app.domain.errors import AccessDeniedError, DependencyError, InvalidBlobNameError, UploadTooLargeError
from secretless_app.infrastructure.memory_adapters import InMemoryBlobStore, InMemorySecretStore
from tests.conftest import SECRET_NAME, SECRET_VALUE
```

What happens, step by step:

- `CheckHealth` from the repository's own module `secretless_app.application.check_health`: Read the partner key and report its length (defined in `src/secretless_app/application/check_health.py`)
- `SaveUpload` from the repository's own module `secretless_app.application.save_upload`: Validate the name and the size, then write the blob (overwriting a blob of the same name) (defined in `src/secretless_app/application/save_upload.py`)
- `AccessDeniedError` from the repository's own module `secretless_app.domain.errors`: The app's identity is known to the service but holds no role that allows the call (defined in `src/secretless_app/domain/errors.py`)
- `DependencyError` from the repository's own module `secretless_app.domain.errors`: An Azure service could not be used; `code` is the service's own error code (defined in `src/secretless_app/domain/errors.py`)
- `InvalidBlobNameError` from the repository's own module `secretless_app.domain.errors`: The requested blob name breaks the naming rule (defined in `src/secretless_app/domain/errors.py`)
- `UploadTooLargeError` from the repository's own module `secretless_app.domain.errors`: The upload is bigger than the configured limit (defined in `src/secretless_app/domain/errors.py`)
- `InMemoryBlobStore` from the repository's own module `secretless_app.infrastructure.memory_adapters`: A dictionary of blobs that can pretend the Blob Data Contributor role was removed (defined in `src/secretless_app/infrastructure/memory_adapters.py`)
- `InMemorySecretStore` from the repository's own module `secretless_app.infrastructure.memory_adapters`: A dictionary of secrets that can pretend the Secrets User role was removed (defined in `src/secretless_app/infrastructure/memory_adapters.py`)
- `SECRET_NAME` from the test helper module `tests.conftest`.
- `SECRET_VALUE` from the test helper module `tests.conftest`.

**Lines 10 to 13**

```python
def test_health_reports_the_length_of_the_key_and_not_the_key():
    report = CheckHealth(InMemorySecretStore({SECRET_NAME: SECRET_VALUE}), SECRET_NAME).run()
    assert report.key_length == len(SECRET_VALUE)
    assert SECRET_VALUE not in repr(report)
```

**Function `test_health_reports_the_length_of_the_key_and_not_the_key`** takes no parameters.

What happens, step by step:

- Sets `report` to the result of calling `CheckHealth(InMemorySecretStore({SECRET_NAME: SECRET_VALUE}), SECRET_NAME).run()`.
- Checks that `report.key_length` equals `len(SECRET_VALUE)`.
- Checks that `SECRET_VALUE` is not inside `repr(report)`.

Names used here:

- `repr(x)` is the unambiguous text form of a value, meant for developers (quotes around strings, for example).

**Lines 16 to 20**

```python
def test_health_surfaces_a_missing_vault_role_as_access_denied():
    check = CheckHealth(InMemorySecretStore({SECRET_NAME: SECRET_VALUE}, denied=True), SECRET_NAME)
    with pytest.raises(AccessDeniedError) as caught:
        check.run()
    assert caught.value.code == "ForbiddenByRbac"
```

**Function `test_health_surfaces_a_missing_vault_role_as_access_denied`** takes no parameters.

**New idea.** `with pytest.raises(SomeError):` is a context manager that expects the block to raise `SomeError`. The test passes only if that error is raised; if nothing is raised or a different error is raised, the test fails. `match="text"` also requires the error message to match the pattern.

What happens, step by step:

- Sets `check` to the result of calling `CheckHealth(InMemorySecretStore({SECRET_NAME: SECRET_VALUE}, denied=True), SECRET_NAME)`.
- Inside a block that expects an error: `pytest.raises(AccessDeniedError)`:
  - Calls `check.run()`.
- Checks that `caught.value.code` equals `'ForbiddenByRbac'`.

**Lines 23 to 27**

```python
def test_health_surfaces_a_missing_secret_as_a_dependency_failure_that_is_not_a_denial():
    with pytest.raises(DependencyError) as caught:
        CheckHealth(InMemorySecretStore({}), SECRET_NAME).run()
    assert caught.value.code == "SecretNotFound"
    assert not isinstance(caught.value, AccessDeniedError)
```

**Function `test_health_surfaces_a_missing_secret_as_a_dependency_failure_that_is_not_a_denial`** takes no parameters.

What happens, step by step:

- Inside a block that expects an error: `pytest.raises(DependencyError)`:
  - Calls `CheckHealth(InMemorySecretStore({}), SECRET_NAME).run()`.
- Checks that `caught.value.code` equals `'SecretNotFound'`.
- Checks that it is not the case that `isinstance(caught.value, AccessDeniedError)` is true.

Names used here:

- `isinstance(x, T)` is true when `x` is a `T` (or a subclass of it).

**Lines 30 to 34**

```python
def test_an_upload_lands_in_the_container_under_its_name():
    blobs = InMemoryBlobStore()
    saved = SaveUpload(blobs, max_bytes=10).run("hello.txt", b"hi there")
    assert saved.value == "hello.txt"
    assert blobs.blobs == {"hello.txt": b"hi there"}
```

**Function `test_an_upload_lands_in_the_container_under_its_name`** takes no parameters.

What happens, step by step:

- Sets `blobs` to the result of calling `InMemoryBlobStore()`.
- Sets `saved` to the result of calling `SaveUpload(blobs, max_bytes=10).run('hello.txt', b'hi there')`.
- Checks that `saved.value` equals `'hello.txt'`.
- Checks that `blobs.blobs` equals `{'hello.txt': b'hi there'}`.

**Lines 37 to 42**

```python
def test_an_upload_overwrites_a_blob_of_the_same_name():
    blobs = InMemoryBlobStore()
    use_case = SaveUpload(blobs, max_bytes=10)
    use_case.run("a.txt", b"one")
    use_case.run("a.txt", b"two")
    assert blobs.blobs == {"a.txt": b"two"}
```

**Function `test_an_upload_overwrites_a_blob_of_the_same_name`** takes no parameters.

What happens, step by step:

- Sets `blobs` to the result of calling `InMemoryBlobStore()`.
- Sets `use_case` to the result of calling `SaveUpload(blobs, max_bytes=10)`.
- Calls `use_case.run('a.txt', b'one')`.
- Calls `use_case.run('a.txt', b'two')`.
- Checks that `blobs.blobs` equals `{'a.txt': b'two'}`.

**Lines 45 to 49**

```python
def test_an_upload_at_the_limit_is_accepted_and_one_byte_over_is_refused():
    use_case = SaveUpload(InMemoryBlobStore(), max_bytes=4)
    use_case.run("ok.bin", b"1234")
    with pytest.raises(UploadTooLargeError):
        use_case.run("big.bin", b"12345")
```

**Function `test_an_upload_at_the_limit_is_accepted_and_one_byte_over_is_refused`** takes no parameters.

What happens, step by step:

- Sets `use_case` to the result of calling `SaveUpload(InMemoryBlobStore(), max_bytes=4)`.
- Calls `use_case.run('ok.bin', b'1234')`.
- Inside a block that expects an error: `pytest.raises(UploadTooLargeError)`:
  - Calls `use_case.run('big.bin', b'12345')`.

**Lines 52 to 56**

```python
def test_a_bad_name_is_refused_before_anything_is_written():
    blobs = InMemoryBlobStore()
    with pytest.raises(InvalidBlobNameError):
        SaveUpload(blobs, max_bytes=10).run("../x", b"data")
    assert blobs.blobs == {}
```

**Function `test_a_bad_name_is_refused_before_anything_is_written`** takes no parameters.

What happens, step by step:

- Sets `blobs` to the result of calling `InMemoryBlobStore()`.
- Inside a block that expects an error: `pytest.raises(InvalidBlobNameError)`:
  - Calls `SaveUpload(blobs, max_bytes=10).run('../x', b'data')`.
- Checks that `blobs.blobs` equals `{}`.

**Lines 59 to 62**

```python
def test_an_upload_surfaces_a_missing_blob_role_as_access_denied():
    with pytest.raises(AccessDeniedError) as caught:
        SaveUpload(InMemoryBlobStore(denied=True), max_bytes=10).run("a.txt", b"data")
    assert caught.value.code == "AuthorizationPermissionMismatch"
```

**Function `test_an_upload_surfaces_a_missing_blob_role_as_access_denied`** takes no parameters.

What happens, step by step:

- Inside a block that expects an error: `pytest.raises(AccessDeniedError)`:
  - Calls `SaveUpload(InMemoryBlobStore(denied=True), max_bytes=10).run('a.txt', b'data')`.
- Checks that `caught.value.code` equals `'AuthorizationPermissionMismatch'`.

#### `tests/unit/domain/test_blob_name_and_secret.py`

22 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
import pytest
```

What happens, step by step:

- `pytest`: the test framework.

**Lines 3 to 5**

```python
from secretless_app.domain.blob_name import BlobName
from secretless_app.domain.errors import InvalidBlobNameError
from secretless_app.domain.secret import Secret
```

What happens, step by step:

- `BlobName` from the repository's own module `secretless_app.domain.blob_name`: A blob name that is safe to use as a path segment: 1 to 128 characters, no slash, no dot-dot (defined in `src/secretless_app/domain/blob_name.py`)
- `InvalidBlobNameError` from the repository's own module `secretless_app.domain.errors`: The requested blob name breaks the naming rule (defined in `src/secretless_app/domain/errors.py`)
- `Secret` from the repository's own module `secretless_app.domain.secret`: Holds a secret string; `repr`, `str` and formatting show a placeholder, `reveal` returns the value (defined in `src/secretless_app/domain/secret.py`)

**Lines 8 to 10**

```python
@pytest.mark.parametrize("value", ["hello.txt", "a", "Report_2026-10.csv", "x" * 128, "v1.2.3.tar.gz"])
def test_a_plain_file_name_is_accepted(value):
    assert BlobName(value).value == value
```

**Function `test_a_plain_file_name_is_accepted`** takes `value`.

**New idea.** `@pytest.mark.parametrize("names", [values...])` is a **decorator** that runs the same test function once for each listed value set. Each run is reported separately, and the values arrive as the function's parameters.

What happens, step by step:

- Decorator `@pytest.mark.parametrize('value', ['hello.txt', 'a', 'Report_2026-10.csv', 'x' * 128, 'v1.2.3.tar.gz'])`.
- Checks that `BlobName(value).value` equals `value`.

**Lines 13 to 19**

```python
@pytest.mark.parametrize(
    "value",
    ["", ".hidden", "-dash", "has space", "a/b", "..", "a..b", "x" * 129, "naïve.txt", "a\nb", "a\\b"],
)
def test_a_name_that_could_escape_or_confuse_the_path_is_refused(value):
    with pytest.raises(InvalidBlobNameError):
        BlobName(value)
```

**Function `test_a_name_that_could_escape_or_confuse_the_path_is_refused`** takes `value`.

What happens, step by step:

- Decorator `@pytest.mark.parametrize('value', ['', '.hidden', '-dash', 'has space', 'a/b', '..', 'a..b', 'x' * 129, 'naïve.txt', 'a\nb', 'a\\b'])`.
- Inside a block that expects an error: `pytest.raises(InvalidBlobNameError)`:
  - Calls `BlobName(value)`.

**Lines 22 to 25**

```python
def test_a_secret_never_shows_its_value_when_printed_or_formatted():
    secret = Secret("hunter2-value")
    for rendering in (repr(secret), str(secret), f"{secret}", f"{secret!r}", "%s" % secret):  # noqa: UP031
        assert "hunter2" not in rendering
```

**Function `test_a_secret_never_shows_its_value_when_printed_or_formatted`** takes no parameters.

**New idea.** `for item in things:` runs its block once for each element of `things`, with `item` set to that element.

What happens, step by step:

- Sets `secret` to the result of calling `Secret('hunter2-value')`.
- For each `rendering` in `(repr(secret), str(secret), f'{secret}', f'{secret!r}', '%s' % secret)`:
  - Checks that `'hunter2'` is not inside `rendering`.

Names used here:

- `str(x)` turns a value into text.

**Lines 28 to 31**

```python
def test_a_secret_reveals_its_value_and_its_length_on_request():
    secret = Secret("hunter2-value")
    assert secret.reveal() == "hunter2-value"
    assert len(secret) == 13
```

**Function `test_a_secret_reveals_its_value_and_its_length_on_request`** takes no parameters.

What happens, step by step:

- Sets `secret` to the result of calling `Secret('hunter2-value')`.
- Checks that `secret.reveal()` equals `'hunter2-value'`.
- Checks that `len(secret)` equals `13`.

Names used here:

- `reveal` is the repository's own: Return the secret itself; call it only where the value is used (defined in `src/secretless_app/domain/secret.py`)

#### `tests/unit/infrastructure/test_azure_adapters.py`

54 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""The adapters against a stub of the SDK client: the call made, and the error translation."""
```

**New idea.** An **SDK** (software development kit) or *client library* is a package of ready-made code that talks to a service for you. The Azure ones turn calls such as "read this secret" into the correct web requests, add the access token and retry transient failures.

**New idea.** A **fake** (or *test double*) is a simple stand-in object used in tests in place of a real service. It behaves like the real one in the ways the test needs, with no network, no account and no cost.

The module docstring says: The adapters against a stub of the SDK client: the call made, and the error translation.

**Lines 3 to 4**

```python
from types import SimpleNamespace
from typing import Any
```

What happens, step by step:

- `SimpleNamespace` from `types`: a plain object whose attributes are set from keywords.
- `Any` from `typing`: the type hint that allows any value.

**Lines 6 to 8**

```python
import pytest
from azure.core.exceptions import ClientAuthenticationError
from azure.identity import DefaultAzureCredential
```

What happens, step by step:

- `pytest`: the test framework.
- `ClientAuthenticationError` from `azure.core.exceptions`: raised when Azure refuses the credential.
- `DefaultAzureCredential` from `azure.identity`: tries several ways to prove identity to Azure and uses the first that works.

**Lines 10 to 12**

```python
from secretless_app.domain.blob_name import BlobName
from secretless_app.domain.errors import DependencyError
from secretless_app.infrastructure.azure_adapters import BlobUploads, KeyVaultSecretStore, build_credential
```

What happens, step by step:

- `BlobName` from the repository's own module `secretless_app.domain.blob_name`: A blob name that is safe to use as a path segment: 1 to 128 characters, no slash, no dot-dot (defined in `src/secretless_app/domain/blob_name.py`)
- `DependencyError` from the repository's own module `secretless_app.domain.errors`: An Azure service could not be used; `code` is the service's own error code (defined in `src/secretless_app/domain/errors.py`)
- `BlobUploads` from the repository's own module `secretless_app.infrastructure.azure_adapters`: Writes blobs with the Storage Blob Data Contributor role on one container (defined in `src/secretless_app/infrastructure/azure_adapters.py`)
- `KeyVaultSecretStore` from the repository's own module `secretless_app.infrastructure.azure_adapters`: Reads secrets with the Key Vault Secrets User role (defined in `src/secretless_app/infrastructure/azure_adapters.py`)
- `build_credential` from the repository's own module `secretless_app.infrastructure.azure_adapters`: In Azure the managed identity named by `client_id` answers; on a laptop `az login` does (defined in `src/secretless_app/infrastructure/azure_adapters.py`)

**Line 15**

```python
class _Credential(DefaultAzureCredential):
```

**Class `_Credential`**, built on `DefaultAzureCredential`.

**New idea.** `class Child(Parent):` makes `Child` **inherit** from `Parent`: it starts with all of the parent's attributes and methods and can add to or replace them. `super()` reaches the parent's version of a method.

**Lines 16 to 17**

```python
    def __init__(self) -> None:  # skip the real credential chain
        pass
```

**Method `__init__`** takes no parameters; gives back `None`.

What happens, step by step:

- `pass`: do nothing.

**Line 20**

```python
class _SecretClient:
```

**Class `_SecretClient`**.

**Lines 21 to 23**

```python
    def __init__(self, value: str | None = "abcd", error: Exception | None = None) -> None:
        self.value, self.error = value, error
        self.asked: list[str] = []
```

**Method `__init__`** takes `value` (type `str | None`), default `'abcd'`, `error` (type `Exception | None`), default `None`; gives back `None`.

What happens, step by step:

- Sets `(self.value, self.error)` to `(value, error)`.
- Sets `self.asked` with type `list[str]` and starting value `[]`.

**Lines 25 to 29**

```python
    def get_secret(self, name: str) -> Any:
        self.asked.append(name)
        if self.error:
            raise self.error
        return SimpleNamespace(value=self.value)
```

**Method `get_secret`** takes `name` (type `str`); gives back `Any`.

**New idea.** `if condition:` runs its block only when the condition is true; `elif` adds another test; `else` is what runs when none matched.

What happens, step by step:

- Calls `self.asked.append(name)`.
- If `self.error` is true:
  - Raises `self.error`.
- Returns `SimpleNamespace(value=self.value)`.

Names used here:

- `.append(x)` adds `x` to the end of a list.

**Line 32**

```python
class _ContainerClient:
```

**Class `_ContainerClient`**.

**Lines 33 to 35**

```python
    def __init__(self, error: Exception | None = None) -> None:
        self.error = error
        self.calls: list[tuple[str, bytes, bool]] = []
```

**Method `__init__`** takes `error` (type `Exception | None`), default `None`; gives back `None`.

What happens, step by step:

- Sets `self.error` to `error`.
- Sets `self.calls` with type `list[tuple[str, bytes, bool]]` and starting value `[]`.

**Lines 37 to 40**

```python
    def upload_blob(self, name: str, data: bytes, overwrite: bool) -> None:
        self.calls.append((name, data, overwrite))
        if self.error:
            raise self.error
```

**Method `upload_blob`** takes `name` (type `str`), `data` (type `bytes`), `overwrite` (type `bool`); gives back `None`.

What happens, step by step:

- Calls `self.calls.append((name, data, overwrite))`.
- If `self.error` is true:
  - Raises `self.error`.

**Lines 43 to 47**

```python
def test_the_vault_adapter_reads_the_named_secret():
    store = KeyVaultSecretStore("https://kv.vault.azure.net", _Credential())
    store._client = client = _SecretClient("abcd")  # type: ignore[assignment]
    assert store.get("partner-api-key").reveal() == "abcd"
    assert client.asked == ["partner-api-key"]
```

**New idea.** **TLS** is the protocol that encrypts a network connection and proves who is on the other end, which is what the `s` in `https` stands for. The server proves its identity with a **certificate**, a signed document that names the server and carries its public key; a client refuses a certificate it cannot trust.

**Function `test_the_vault_adapter_reads_the_named_secret`** takes no parameters.

What happens, step by step:

- Sets `store` to the result of calling `KeyVaultSecretStore('https://kv.vault.azure.net', _Credential())`.
- Sets `store._client`, `client` to the result of calling `_SecretClient('abcd')`.
- Checks that `store.get('partner-api-key').reveal()` equals `'abcd'`.
- Checks that `client.asked` equals `['partner-api-key']`.

**Lines 50 to 55**

```python
def test_the_vault_adapter_translates_sdk_errors():
    store = KeyVaultSecretStore("https://kv.vault.azure.net", _Credential())
    store._client = _SecretClient(error=ClientAuthenticationError("no token"))  # type: ignore[assignment]
    with pytest.raises(DependencyError) as caught:
        store.get("partner-api-key")
    assert caught.value.service == "keyvault"
```

**New idea.** An **access token** is a short-lived piece of text, issued by an identity service after you prove who you are, that you attach to a request to show that you are allowed to make it. It expires after about an hour, so a stolen one is far less dangerous than a password.

**Function `test_the_vault_adapter_translates_sdk_errors`** takes no parameters.

What happens, step by step:

- Sets `store` to the result of calling `KeyVaultSecretStore('https://kv.vault.azure.net', _Credential())`.
- Sets `store._client` to the result of calling `_SecretClient(error=ClientAuthenticationError('no token'))`.
- Inside a block that expects an error: `pytest.raises(DependencyError)`:
  - Calls `store.get('partner-api-key')`.
- Checks that `caught.value.service` equals `'keyvault'`.

Names used here:

- `ClientAuthenticationError` is the Azure SDK error for a refused credential.

**Lines 58 to 62**

```python
def test_the_blob_adapter_overwrites_by_name():
    uploads = BlobUploads("https://st.blob.core.windows.net", "uploads", _Credential())
    uploads._container = client = _ContainerClient()  # type: ignore[assignment]
    uploads.put(BlobName("a.txt"), b"data")
    assert client.calls == [("a.txt", b"data", True)]
```

**Function `test_the_blob_adapter_overwrites_by_name`** takes no parameters.

What happens, step by step:

- Sets `uploads` to the result of calling `BlobUploads('https://st.blob.core.windows.net', 'uploads', _Credential())`.
- Sets `uploads._container`, `client` to the result of calling `_ContainerClient()`.
- Calls `uploads.put(BlobName('a.txt'), b'data')`.
- Checks that `client.calls` equals `[('a.txt', b'data', True)]`.

**Lines 65 to 70**

```python
def test_the_blob_adapter_translates_sdk_errors():
    uploads = BlobUploads("https://st.blob.core.windows.net", "uploads", _Credential())
    uploads._container = _ContainerClient(ClientAuthenticationError("no token"))  # type: ignore[assignment]
    with pytest.raises(DependencyError) as caught:
        uploads.put(BlobName("a.txt"), b"data")
    assert caught.value.service == "blob"
```

**Function `test_the_blob_adapter_translates_sdk_errors`** takes no parameters.

What happens, step by step:

- Sets `uploads` to the result of calling `BlobUploads('https://st.blob.core.windows.net', 'uploads', _Credential())`.
- Sets `uploads._container` to the result of calling `_ContainerClient(ClientAuthenticationError('no token'))`.
- Inside a block that expects an error: `pytest.raises(DependencyError)`:
  - Calls `uploads.put(BlobName('a.txt'), b'data')`.
- Checks that `caught.value.service` equals `'blob'`.

**Lines 73 to 75**

```python
def test_the_credential_is_built_without_any_secret_and_without_network_access():
    assert isinstance(build_credential("00000000-0000-0000-0000-000000000000"), DefaultAzureCredential)
    assert isinstance(build_credential(None), DefaultAzureCredential)
```

**Function `test_the_credential_is_built_without_any_secret_and_without_network_access`** takes no parameters.

What happens, step by step:

- Checks that `isinstance(build_credential('00000000-0000-0000-0000-000000000000'), DefaultAzureCredential)` is true.
- Checks that `isinstance(build_credential(None), DefaultAzureCredential)` is true.

#### `tests/unit/infrastructure/test_azure_errors.py`

65 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
from typing import Any, cast
```

What happens, step by step:

- `Any` from `typing`: the type hint that allows any value.
- `cast` from `typing`: tells the type checker "treat this value as that type" (it does nothing at run time).

**Lines 3 to 10**

```python
import pytest
from azure.core.exceptions import (
    ClientAuthenticationError,
    HttpResponseError,
    ResourceNotFoundError,
    ServiceRequestError,
)
from azure.identity import CredentialUnavailableError
```

**New idea.** **DNS** (the Domain Name System) is the network's telephone book: it turns a name such as `myvault.vault.azure.net` into the IP address a computer connects to. Asking it is called *resolving* the name, and the answer depends on which network and which name server you ask.

What happens, step by step:

- `pytest`: the test framework.
- `ClientAuthenticationError` from `azure.core.exceptions`: raised when Azure refuses the credential.
- `HttpResponseError` from `azure.core.exceptions`: raised for any HTTP error reply; `.status_code` holds the number.
- `ResourceNotFoundError` from `azure.core.exceptions`: raised for HTTP 404 (the thing asked for does not exist).
- `ServiceRequestError` from `azure.core.exceptions`: raised when a request could not be sent (network or DNS failure).
- `CredentialUnavailableError` from `azure.identity`: raised when a credential source (such as the managed identity endpoint) is not available here.

**Lines 12 to 13**

```python
from secretless_app.domain.errors import AccessDeniedError, DependencyError
from secretless_app.infrastructure.azure_errors import translate
```

What happens, step by step:

- `AccessDeniedError` from the repository's own module `secretless_app.domain.errors`: The app's identity is known to the service but holds no role that allows the call (defined in `src/secretless_app/domain/errors.py`)
- `DependencyError` from the repository's own module `secretless_app.domain.errors`: An Azure service could not be used; `code` is the service's own error code (defined in `src/secretless_app/domain/errors.py`)
- `translate` from the repository's own module `secretless_app.infrastructure.azure_errors`: Return `AccessDeniedError` for HTTP 403, `DependencyError` for everything else (defined in `src/secretless_app/infrastructure/azure_errors.py`)

**Line 16**

```python
class _Response:  # the three attributes the SDK reads from a response
```

**Class `_Response`**.

**Lines 17 to 21**

```python
    def __init__(self, status_code: int, reason: str = "") -> None:
        self.status_code = status_code
        self.reason = reason
        self.headers: dict[str, str] = {}
        self.content_type = "application/json"
```

**Method `__init__`** takes `status_code` (type `int`), `reason` (type `str`), default `''`; gives back `None`.

What happens, step by step:

- Sets `self.status_code` to `status_code`.
- Sets `self.reason` to `reason`.
- Sets `self.headers` with type `dict[str, str]` and starting value `{}`.
- Sets `self.content_type` to `'application/json'`.

**Lines 23 to 24**

```python
    def text(self) -> str:
        return ""
```

**Method `text`** takes no parameters; gives back `str`.

What happens, step by step:

- Returns `''`.

**Lines 27 to 28**

```python
def _response(status_code: int, reason: str) -> Any:
    return cast(Any, _Response(status_code, reason))
```

**Function `_response`** takes `status_code` (type `int`), `reason` (type `str`); gives back `Any`.

What happens, step by step:

- Returns `cast(Any, _Response(status_code, reason))`.

**Lines 31 to 39**

```python
def _vault_forbidden() -> HttpResponseError:
    error = HttpResponseError(
        message="(Forbidden) Caller is not authorized to perform action on resource.\n"
        "Caller: appid=1111;oid=2222;iss=https://sts.windows.net/3333/\n"
        "Action: 'Microsoft.KeyVault/vaults/secrets/getSecret/action'",
        response=_response(403, "Forbidden"),
    )
    error.error = type("Odata", (), {"code": "Forbidden", "innererror": {"code": "ForbiddenByRbac"}})()
    return error
```

**Function `_vault_forbidden`** takes no parameters; gives back `HttpResponseError`.

What happens, step by step:

- Sets `error` to the result of calling `HttpResponseError` with `message` set to `"(Forbidden) Caller is not authorized to perform action on resource.\nCaller: appid=1111;oid=2222;iss=https:/…` (long; see the quote); `response` set to `_response(403, 'Forbidden')`.
- Sets `error.error` to the result of calling `type('Odata', (), {'code': 'Forbidden', 'innererror': {'code': 'ForbiddenByRbac'}})()`.
- Returns `error`.

Names used here:

- `HttpResponseError` is the Azure SDK's error for an HTTP reply with an error status; `.status_code` holds the number.
- `type(x)` is the class of `x`.

**Lines 42 to 48**

```python
def _blob_forbidden() -> HttpResponseError:
    error = HttpResponseError(
        message="This request is not authorized to perform this operation using this permission.",
        response=_response(403, "This request is not authorized to perform this operation using this permission."),
    )
    error.error_code = "AuthorizationPermissionMismatch"  # type: ignore[attr-defined]
    return error
```

**Function `_blob_forbidden`** takes no parameters; gives back `HttpResponseError`.

What happens, step by step:

- Sets `error` to the result of calling `HttpResponseError` with `message` set to `'This request is not authorized to perform this operation using this permission.'`; `response` set to `_response(403, 'This request is not authorized to perform this operation using this permission.')`.
- Sets `error.error_code` to `'AuthorizationPermissionMismatch'`.
- Returns `error`.

**Lines 51 to 56**

```python
def test_a_vault_403_becomes_access_denied_with_the_rbac_code_and_the_caller_in_the_detail():
    result = translate("keyvault", _vault_forbidden())
    assert isinstance(result, AccessDeniedError)
    assert result.code == "ForbiddenByRbac"
    assert "oid=2222" in result.detail
    assert "getSecret" in result.detail
```

**Function `test_a_vault_403_becomes_access_denied_with_the_rbac_code_and_the_caller_in_the_detail`** takes no parameters.

What happens, step by step:

- Sets `result` to the result of calling `translate('keyvault', _vault_forbidden())`.
- Checks that `isinstance(result, AccessDeniedError)` is true.
- Checks that `result.code` equals `'ForbiddenByRbac'`.
- Checks that `'oid=2222'` is one of / is inside `result.detail`.
- Checks that `'getSecret'` is one of / is inside `result.detail`.

**Lines 59 to 62**

```python
def test_a_blob_403_becomes_access_denied_with_the_storage_error_code():
    result = translate("blob", _blob_forbidden())
    assert isinstance(result, AccessDeniedError)
    assert result.code == "AuthorizationPermissionMismatch"
```

**Function `test_a_blob_403_becomes_access_denied_with_the_storage_error_code`** takes no parameters.

What happens, step by step:

- Sets `result` to the result of calling `translate('blob', _blob_forbidden())`.
- Checks that `isinstance(result, AccessDeniedError)` is true.
- Checks that `result.code` equals `'AuthorizationPermissionMismatch'`.

**Lines 65 to 68**

```python
def test_a_404_is_a_dependency_failure_and_not_a_denial():
    result = translate("keyvault", ResourceNotFoundError(message="gone", response=_response(404, "Not Found")))
    assert type(result) is DependencyError
    assert result.code == "Not Found"
```

**Function `test_a_404_is_a_dependency_failure_and_not_a_denial`** takes no parameters.

**New idea.** `x is None` tests whether `x` is exactly the object `None` (identity), as opposed to `==`, which tests equal value.

What happens, step by step:

- Sets `result` to the result of calling `translate('keyvault', ResourceNotFoundError(message='gone', response=_response(404, 'Not Found')))`.
- Checks that `type(result)` is exactly `DependencyError`.
- Checks that `result.code` equals `'Not Found'`.

Names used here:

- `ResourceNotFoundError` is the Azure SDK error for HTTP 404.

**Lines 71 to 75**

```python
def test_a_credential_that_cannot_get_a_token_is_an_authentication_failure():
    for error in (ClientAuthenticationError("no token"), CredentialUnavailableError("no source")):
        result = translate("blob", error)
        assert type(result) is DependencyError
        assert result.code == "AuthenticationFailed"
```

**Function `test_a_credential_that_cannot_get_a_token_is_an_authentication_failure`** takes no parameters.

What happens, step by step:

- For each `error` in `(ClientAuthenticationError('no token'), CredentialUnavailableError('no source'))`:
  - Sets `result` to the result of calling `translate('blob', error)`.
  - Checks that `type(result)` is exactly `DependencyError`.
  - Checks that `result.code` equals `'AuthenticationFailed'`.

**Lines 78 to 80**

```python
def test_a_network_error_is_unreachable():
    result = translate("blob", ServiceRequestError("connection refused"))
    assert result.code == "Unreachable"  # type: ignore[attr-defined]
```

**Function `test_a_network_error_is_unreachable`** takes no parameters.

What happens, step by step:

- Sets `result` to the result of calling `translate('blob', ServiceRequestError('connection refused'))`.
- Checks that `result.code` equals `'Unreachable'`.

Names used here:

- `ServiceRequestError` is the Azure SDK error for a request that never reached the service (network or DNS problem).

**Lines 83 to 85**

```python
def test_an_unexpected_exception_is_not_swallowed():
    with pytest.raises(ZeroDivisionError):
        translate("blob", ZeroDivisionError())
```

**Function `test_an_unexpected_exception_is_not_swallowed`** takes no parameters.

What happens, step by step:

- Inside a block that expects an error: `pytest.raises(ZeroDivisionError)`:
  - Calls `translate('blob', ZeroDivisionError())`.

**Lines 88 to 90**

```python
def test_a_very_long_message_is_cut_so_one_log_line_stays_bounded():
    error = ServiceRequestError("x" * 10_000)
    assert len(translate("blob", error).detail) == 2000  # type: ignore[attr-defined]
```

**Function `test_a_very_long_message_is_cut_so_one_log_line_stays_bounded`** takes no parameters.

What happens, step by step:

- Sets `error` to the result of calling `ServiceRequestError('x' * 10000)`.
- Checks that `len(translate('blob', error).detail)` equals `2000`.

#### `tests/unit/infrastructure/test_logging_and_wiring.py`

41 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 2**

```python
import json
import logging
```

What happens, step by step:

- `json`: the standard-library module for JSON.
- `logging`: the standard-library module for log records.

**Lines 4 to 7**

```python
from secretless_app.infrastructure.logging import JsonFormatter, configure_logging
from secretless_app.infrastructure.memory_adapters import DEMO_SECRET_VALUE
from secretless_app.infrastructure.settings import Settings
from secretless_app.infrastructure.wiring import build_services
```

What happens, step by step:

- `JsonFormatter` from the repository's own module `secretless_app.infrastructure.logging`: Render a record as JSON; fields passed through `extra=` become top-level keys (defined in `src/secretless_app/infrastructure/logging.py`)
- `configure_logging` from the repository's own module `secretless_app.infrastructure.logging`: Send the root logger to stdout as JSON at `level`; calling it twice does not duplicate lines (defined in `src/secretless_app/infrastructure/logging.py`)
- `DEMO_SECRET_VALUE` from the repository's own module `secretless_app.infrastructure.memory_adapters`.
- `Settings` from the repository's own module `secretless_app.infrastructure.settings`: Everything the app reads from the environment (defined in `src/secretless_app/infrastructure/settings.py`)
- `build_services` from the repository's own module `secretless_app.infrastructure.wiring`: Return the use cases wired to Azure (`BACKEND=azure`) or to memory (`BACKEND=memory`) (defined in `src/secretless_app/infrastructure/wiring.py`)

**Lines 10 to 19**

```python
def test_a_record_becomes_one_json_line_with_its_extra_fields_on_top():
    record = logging.LogRecord("app", logging.ERROR, __file__, 1, "access denied by %s", ("blob",), None)
    record.code = "AuthorizationPermissionMismatch"
    line = JsonFormatter().format(record)
    payload = json.loads(line)
    assert "\n" not in line
    assert payload["level"] == "ERROR"
    assert payload["msg"] == "access denied by blob"
    assert payload["code"] == "AuthorizationPermissionMismatch"
    assert payload["ts"].endswith("+00:00")
```

**Function `test_a_record_becomes_one_json_line_with_its_extra_fields_on_top`** takes no parameters.

What happens, step by step:

- Sets `record` to the result of calling `logging.LogRecord('app', logging.ERROR, __file__, 1, 'access denied by %s', ('blob',), None)`.
- Sets `record.code` to `'AuthorizationPermissionMismatch'`.
- Sets `line` to the result of calling `JsonFormatter().format(record)`.
- Sets `payload` to the result of calling `json.loads(line)`.
- Checks that `'\n'` is not inside `line`.
- Checks that `payload['level']` equals `'ERROR'`.
- Checks that `payload['msg']` equals `'access denied by blob'`.
- Checks that `payload['code']` equals `'AuthorizationPermissionMismatch'`.
- Checks that `payload['ts'].endswith('+00:00')` is true.

Names used here:

- A `LogRecord` holds everything about one log call: level, message, time, extra fields.
- `format` is the repository's own: Return the JSON line for `record` (defined in `src/secretless_app/infrastructure/logging.py`)
- `.endswith(suffix)` is true when the text ends with `suffix`.

**Lines 22 to 29**

```python
def test_an_exception_is_included_as_text():
    try:
        raise ValueError("boom")
    except ValueError:
        import sys

        record = logging.LogRecord("app", logging.ERROR, __file__, 1, "failed", (), sys.exc_info())
    assert "ValueError: boom" in json.loads(JsonFormatter().format(record))["exc"]
```

**Function `test_an_exception_is_included_as_text`** takes no parameters.

What happens, step by step:

- Try:
  - Raises `ValueError('boom')`.
- If `ValueError` is raised:
  - Imports `sys`.
  - Sets `record` to the result of calling `logging.LogRecord('app', logging.ERROR, __file__, 1, 'failed', (), sys.exc_info())`.
- Checks that `'ValueError: boom'` is one of / is inside `json.loads(JsonFormatter().format(record))['exc']`.

Names used here:

- `ValueError` is Python's error for a value of the right type but unacceptable content.

**Lines 32 to 37**

```python
def test_configuring_twice_leaves_one_handler(capsys):
    configure_logging("INFO")
    configure_logging("DEBUG")
    assert len(logging.getLogger().handlers) == 1
    assert logging.getLogger().level == logging.DEBUG
    configure_logging("INFO")
```

**Function `test_configuring_twice_leaves_one_handler`** takes `capsys`.

**New idea.** `capsys` is a built-in pytest fixture that captures what the code prints to standard output and standard error, so a test can read it with `capsys.readouterr()`.

**New idea.** `logging.getLogger("name")` returns the logger with that name. Code writes records with `.info`, `.warning`, `.error`; handlers decide where the records go and in what format.

What happens, step by step:

- Calls `configure_logging('INFO')`.
- Calls `configure_logging('DEBUG')`.
- Checks that `len(logging.getLogger().handlers)` equals `1`.
- Checks that `logging.getLogger().level` equals `logging.DEBUG`.
- Calls `configure_logging('INFO')`.

Names used here:

- `logging.getLogger(name)` returns the named logger.

**Lines 40 to 42**

```python
def test_the_memory_backend_wires_a_working_demo_vault():
    services = build_services(Settings.from_env({"BACKEND": "memory"}))
    assert services.check_health.run().key_length == len(DEMO_SECRET_VALUE)
```

**Function `test_the_memory_backend_wires_a_working_demo_vault`** takes no parameters.

What happens, step by step:

- Sets `services` to the result of calling `build_services(Settings.from_env({'BACKEND': 'memory'}))`.
- Checks that `services.check_health.run().key_length` equals `len(DEMO_SECRET_VALUE)`.

**Lines 45 to 53**

```python
def test_the_azure_backend_wires_without_contacting_azure():
    settings = Settings.from_env(
        {
            "VAULT_URL": "https://kv-test.vault.azure.net",
            "STORAGE_URL": "https://sttest.blob.core.windows.net",
        }
    )
    services = build_services(settings)
    assert services.check_health.secret_name == "partner-api-key"
```

**Function `test_the_azure_backend_wires_without_contacting_azure`** takes no parameters.

What happens, step by step:

- Sets `settings` to the result of calling `Settings.from_env` with `{'VAULT_URL': 'https://kv-test.vault.azure.net', 'STORAGE_URL': 'https://sttest.blob.core.windows.net'}`.
- Sets `services` to the result of calling `build_services(settings)`.
- Checks that `services.check_health.secret_name` equals `'partner-api-key'`.

#### `tests/unit/infrastructure/test_settings.py`

37 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
import pytest
```

What happens, step by step:

- `pytest`: the test framework.

**Line 3**

```python
from secretless_app.infrastructure.settings import ConfigError, Settings
```

What happens, step by step:

- `ConfigError` from the repository's own module `secretless_app.infrastructure.settings`: One or more settings are missing or malformed; the message lists all of them (defined in `src/secretless_app/infrastructure/settings.py`)
- `Settings` from the repository's own module `secretless_app.infrastructure.settings`: Everything the app reads from the environment (defined in `src/secretless_app/infrastructure/settings.py`)

**Lines 5 to 9**

```python
AZURE_ENV = {
    "VAULT_URL": "https://kv-secretless-12345.vault.azure.net",
    "STORAGE_URL": "https://stsecretless12345.blob.core.windows.net",
    "AZURE_CLIENT_ID": "00000000-0000-0000-0000-000000000000",
}
```

What happens, step by step:

- Sets `AZURE_ENV` to `{'VAULT_URL': 'https://kv-secretless-12345.vault.azure.net', 'STORAGE_URL': 'https://stsecretless12345.blob.c…` (long; see the quote).

**Lines 12 to 19**

```python
def test_azure_settings_read_the_three_addresses_and_apply_defaults():
    settings = Settings.from_env(AZURE_ENV)
    assert settings.backend == "azure"
    assert settings.vault_url == AZURE_ENV["VAULT_URL"]
    assert settings.container == "uploads"
    assert settings.secret_name == "partner-api-key"
    assert settings.max_upload_bytes == 5_000_000
    assert settings.log_level == "INFO"
```

**Function `test_azure_settings_read_the_three_addresses_and_apply_defaults`** takes no parameters.

What happens, step by step:

- Sets `settings` to the result of calling `Settings.from_env(AZURE_ENV)`.
- Checks that `settings.backend` equals `'azure'`.
- Checks that `settings.vault_url` equals `AZURE_ENV['VAULT_URL']`.
- Checks that `settings.container` equals `'uploads'`.
- Checks that `settings.secret_name` equals `'partner-api-key'`.
- Checks that `settings.max_upload_bytes` equals `5000000`.
- Checks that `settings.log_level` equals `'INFO'`.

**Lines 22 to 24**

```python
def test_the_client_id_is_optional_because_a_laptop_signs_in_with_az_login():
    env = {key: value for key, value in AZURE_ENV.items() if key != "AZURE_CLIENT_ID"}
    assert Settings.from_env(env).client_id is None
```

**Function `test_the_client_id_is_optional_because_a_laptop_signs_in_with_az_login`** takes no parameters.

What happens, step by step:

- Sets `env` to `{key: value for key, value in AZURE_ENV.items() if key != 'AZURE_CLIENT_ID'}`.
- Checks that `Settings.from_env(env).client_id` is exactly `None`.

Names used here:

- `.items()` on a dictionary lists its `(key, value)` pairs.

**Lines 27 to 34**

```python
def test_every_problem_is_reported_at_once():
    with pytest.raises(ConfigError) as caught:
        Settings.from_env({"VAULT_URL": "http://insecure", "MAX_UPLOAD_BYTES": "-3", "LOG_LEVEL": "LOUD"})
    message = str(caught.value)
    assert "VAULT_URL" in message
    assert "STORAGE_URL" in message
    assert "MAX_UPLOAD_BYTES" in message
    assert "LOG_LEVEL" in message
```

**Function `test_every_problem_is_reported_at_once`** takes no parameters.

What happens, step by step:

- Inside a block that expects an error: `pytest.raises(ConfigError)`:
  - Calls `Settings.from_env({'VAULT_URL': 'http://insecure', 'MAX_UPLOAD_BYTES': '-3', 'LOG_LEVEL': 'LOUD'})`.
- Sets `message` to the result of calling `str(caught.value)`.
- Checks that `'VAULT_URL'` is one of / is inside `message`.
- Checks that `'STORAGE_URL'` is one of / is inside `message`.
- Checks that `'MAX_UPLOAD_BYTES'` is one of / is inside `message`.
- Checks that `'LOG_LEVEL'` is one of / is inside `message`.

**Lines 37 to 40**

```python
def test_the_memory_backend_needs_no_addresses():
    settings = Settings.from_env({"BACKEND": "memory", "MEMORY_DENY": "blob,vault"})
    assert settings.vault_url is None
    assert settings.memory_deny == {"blob", "vault"}
```

**Function `test_the_memory_backend_needs_no_addresses`** takes no parameters.

What happens, step by step:

- Sets `settings` to the result of calling `Settings.from_env({'BACKEND': 'memory', 'MEMORY_DENY': 'blob,vault'})`.
- Checks that `settings.vault_url` is exactly `None`.
- Checks that `settings.memory_deny` equals `{'blob', 'vault'}`.

**Lines 43 to 49**

```python
@pytest.mark.parametrize(
    "env",
    [{"BACKEND": "memory", "MEMORY_DENY": "queue"}, {"BACKEND": "carrier-pigeon"}],
)
def test_unknown_choices_are_refused(env):
    with pytest.raises(ConfigError):
        Settings.from_env(env)
```

**Function `test_unknown_choices_are_refused`** takes `env`.

What happens, step by step:

- Decorator `@pytest.mark.parametrize('env', [{'BACKEND': 'memory', 'MEMORY_DENY': 'queue'}, {'BACKEND': 'carrier-pigeon'}])`.
- Inside a block that expects an error: `pytest.raises(ConfigError)`:
  - Calls `Settings.from_env(env)`.

#### `tests/unit/interfaces/test_http.py`

74 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 2**

```python
import json
import logging
```

What happens, step by step:

- `json`: the standard-library module for JSON.
- `logging`: the standard-library module for log records.

**Line 4**

```python
import pytest
```

What happens, step by step:

- `pytest`: the test framework.

**Lines 6 to 11**

```python
from secretless_app.application.check_health import CheckHealth
from secretless_app.application.save_upload import SaveUpload
from secretless_app.application.services import Services
from secretless_app.infrastructure.memory_adapters import InMemoryBlobStore, InMemorySecretStore
from secretless_app.interfaces.http import create_app
from tests.conftest import SECRET_NAME, SECRET_VALUE
```

What happens, step by step:

- `CheckHealth` from the repository's own module `secretless_app.application.check_health`: Read the partner key and report its length (defined in `src/secretless_app/application/check_health.py`)
- `SaveUpload` from the repository's own module `secretless_app.application.save_upload`: Validate the name and the size, then write the blob (overwriting a blob of the same name) (defined in `src/secretless_app/application/save_upload.py`)
- `Services` from the repository's own module `secretless_app.application.services`: Every use case of the app (defined in `src/secretless_app/application/services.py`)
- `InMemoryBlobStore` from the repository's own module `secretless_app.infrastructure.memory_adapters`: A dictionary of blobs that can pretend the Blob Data Contributor role was removed (defined in `src/secretless_app/infrastructure/memory_adapters.py`)
- `InMemorySecretStore` from the repository's own module `secretless_app.infrastructure.memory_adapters`: A dictionary of secrets that can pretend the Secrets User role was removed (defined in `src/secretless_app/infrastructure/memory_adapters.py`)
- `create_app` from the repository's own module `secretless_app.interfaces.http`: Build the app around `services`; uploads above `max_upload_bytes` are refused before they are read (defined in `src/secretless_app/interfaces/http.py`)
- `SECRET_NAME` from the test helper module `tests.conftest`.
- `SECRET_VALUE` from the test helper module `tests.conftest`.

**Lines 14 to 16**

```python
@pytest.fixture
def client(services):
    return create_app(services, max_upload_bytes=1024).test_client()
```

**Function `client`** takes `services`.

What happens, step by step:

- Decorator `@pytest.fixture`.
- Returns `create_app(services, max_upload_bytes=1024).test_client()`.

Names used here:

- `app.test_client()` is a fake browser that calls the app in-process, without opening a network port.

**Lines 19 to 24**

```python
def _denied_client(*, vault: bool = False, blob: bool = False):
    services = Services(
        CheckHealth(InMemorySecretStore({SECRET_NAME: SECRET_VALUE}, denied=vault), SECRET_NAME),
        SaveUpload(InMemoryBlobStore(denied=blob), max_bytes=1024),
    )
    return create_app(services, max_upload_bytes=1024).test_client()
```

**Function `_denied_client`** takes `vault` (by name only), type `bool`, default `False`, `blob` (by name only), type `bool`, default `False`.

**New idea.** A bare `*` in a parameter list means every parameter after it must be passed by name (`f(x=1)`) and cannot be passed by position. This prevents mixing up arguments.

What happens, step by step:

- Sets `services` to the result of calling `Services` with `CheckHealth(InMemorySecretStore({SECRET_NAME: SECRET_VALUE}, denied=vault), SECRET_NAME)`; `SaveUpload(InMemoryBlobStore(denied=blob), max_bytes=1024)`.
- Returns `create_app(services, max_upload_bytes=1024).test_client()`.

**Lines 27 to 31**

```python
def test_health_returns_the_key_length_and_never_the_key(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok", "key_length": len(SECRET_VALUE)}
    assert SECRET_VALUE not in response.get_data(as_text=True)
```

**Function `test_health_returns_the_key_length_and_never_the_key`** takes `client`.

What happens, step by step:

- Sets `response` to the result of calling `client.get('/health')`.
- Checks that `response.status_code` equals `200`.
- Checks that `response.get_json()` equals `{'status': 'ok', 'key_length': len(SECRET_VALUE)}`.
- Checks that `SECRET_VALUE` is not inside `response.get_data(as_text=True)`.

Names used here:

- `request.get_data()` reads the raw bytes of the request body.

**Lines 34 to 36**

```python
def test_live_answers_without_touching_a_dependency():
    client = _denied_client(vault=True, blob=True)
    assert client.get("/live").get_json() == {"status": "alive"}
```

**Function `test_live_answers_without_touching_a_dependency`** takes no parameters.

What happens, step by step:

- Sets `client` to the result of calling `_denied_client(vault=True, blob=True)`.
- Checks that `client.get('/live').get_json()` equals `{'status': 'alive'}`.

**Lines 39 to 43**

```python
def test_an_upload_returns_201_and_stores_the_body(client, blobs):
    response = client.post("/upload/hello.txt", data=b"hello")
    assert response.status_code == 201
    assert response.get_json() == {"saved": "hello.txt"}
    assert blobs.blobs == {"hello.txt": b"hello"}
```

**Function `test_an_upload_returns_201_and_stores_the_body`** takes `client`, `blobs`.

What happens, step by step:

- Sets `response` to the result of calling `client.post('/upload/hello.txt', data=b'hello')`.
- Checks that `response.status_code` equals `201`.
- Checks that `response.get_json()` equals `{'saved': 'hello.txt'}`.
- Checks that `blobs.blobs` equals `{'hello.txt': b'hello'}`.

**Lines 46 to 49**

```python
def test_a_bad_name_is_a_400(client):
    response = client.post("/upload/.hidden", data=b"x")
    assert response.status_code == 400
    assert response.get_json()["error"] == "invalid_name"
```

**Function `test_a_bad_name_is_a_400`** takes `client`.

What happens, step by step:

- Sets `response` to the result of calling `client.post('/upload/.hidden', data=b'x')`.
- Checks that `response.status_code` equals `400`.
- Checks that `response.get_json()['error']` equals `'invalid_name'`.

**Lines 52 to 56**

```python
def test_a_body_over_the_limit_is_a_413_before_the_app_reads_it(client, blobs):
    response = client.post("/upload/big.bin", data=b"x" * 2048)
    assert response.status_code == 413
    assert response.get_json()["error"] == "upload_too_large"
    assert blobs.blobs == {}
```

**Function `test_a_body_over_the_limit_is_a_413_before_the_app_reads_it`** takes `client`, `blobs`.

What happens, step by step:

- Sets `response` to the result of calling `client.post('/upload/big.bin', data=b'x' * 2048)`.
- Checks that `response.status_code` equals `413`.
- Checks that `response.get_json()['error']` equals `'upload_too_large'`.
- Checks that `blobs.blobs` equals `{}`.

**Lines 59 to 70**

```python
def test_a_missing_blob_role_is_a_502_with_the_code_and_the_detail_only_in_the_log(caplog):
    with caplog.at_level(logging.ERROR, logger="secretless_app.http"):
        response = _denied_client(blob=True).post("/upload/a.txt", data=b"x")
    assert response.status_code == 502
    assert response.get_json() == {
        "error": "upstream_access_denied",
        "service": "blob",
        "code": "AuthorizationPermissionMismatch",
    }
    record = caplog.records[-1]
    assert record.service == "blob"
    assert "not authorized" in record.detail
```

**Function `test_a_missing_blob_role_is_a_502_with_the_code_and_the_detail_only_in_the_log`** takes `caplog`.

**New idea.** `caplog` is a built-in pytest fixture that collects the log records written during the test so the test can check them (`caplog.records`, `caplog.text`).

What happens, step by step:

- Inside a block that `caplog.at_level(logging.ERROR, logger='secretless_app.http')`:
  - Sets `response` to the result of calling `_denied_client(blob=True).post('/upload/a.txt', data=b'x')`.
- Checks that `response.status_code` equals `502`.
- Checks that `response.get_json()` equals `{'error': 'upstream_access_denied', 'service': 'blob', 'code': 'AuthorizationPermissionMismatch'}`.
- Sets `record` to `caplog.records[-1]`.
- Checks that `record.service` equals `'blob'`.
- Checks that `'not authorized'` is one of / is inside `record.detail`.

**Lines 73 to 76**

```python
def test_a_missing_vault_role_is_a_502_naming_the_rbac_code():
    response = _denied_client(vault=True).get("/health")
    assert response.status_code == 502
    assert response.get_json()["code"] == "ForbiddenByRbac"
```

**Function `test_a_missing_vault_role_is_a_502_naming_the_rbac_code`** takes no parameters.

What happens, step by step:

- Sets `response` to the result of calling `_denied_client(vault=True).get('/health')`.
- Checks that `response.status_code` equals `502`.
- Checks that `response.get_json()['code']` equals `'ForbiddenByRbac'`.

**Lines 79 to 86**

```python
def test_a_missing_secret_is_a_502_that_is_not_a_denial():
    services = Services(
        CheckHealth(InMemorySecretStore({}), SECRET_NAME),
        SaveUpload(InMemoryBlobStore(), max_bytes=1024),
    )
    response = create_app(services, max_upload_bytes=1024).test_client().get("/health")
    assert response.status_code == 502
    assert response.get_json()["error"] == "upstream_failure"
```

**Function `test_a_missing_secret_is_a_502_that_is_not_a_denial`** takes no parameters.

What happens, step by step:

- Sets `services` to the result of calling `Services` with `CheckHealth(InMemorySecretStore({}), SECRET_NAME)`; `SaveUpload(InMemoryBlobStore(), max_bytes=1024)`.
- Sets `response` to the result of calling `create_app(services, max_upload_bytes=1024).test_client().get('/health')`.
- Checks that `response.status_code` equals `502`.
- Checks that `response.get_json()['error']` equals `'upstream_failure'`.

**Lines 89 to 91**

```python
def test_unknown_routes_and_wrong_methods_answer_in_json(client):
    assert client.get("/nope").get_json() == {"error": "not_found"}
    assert client.get("/upload/a.txt").status_code == 405
```

**Function `test_unknown_routes_and_wrong_methods_answer_in_json`** takes `client`.

What happens, step by step:

- Checks that `client.get('/nope').get_json()` equals `{'error': 'not_found'}`.
- Checks that `client.get('/upload/a.txt').status_code` equals `405`.

**Lines 94 to 100**

```python
def test_every_request_is_logged_with_status_and_duration(client, caplog):
    with caplog.at_level(logging.INFO, logger="secretless_app.http"):
        client.get("/live")
    record = caplog.records[-1]
    assert (record.method, record.path, record.status) == ("GET", "/live", 200)
    assert record.duration_ms >= 0
    json.dumps(record.__dict__, default=str)  # the whole record serializes
```

**Function `test_every_request_is_logged_with_status_and_duration`** takes `client`, `caplog`.

What happens, step by step:

- Inside a block that `caplog.at_level(logging.INFO, logger='secretless_app.http')`:
  - Calls `client.get('/live')`.
- Sets `record` to `caplog.records[-1]`.
- Checks that `(record.method, record.path, record.status)` equals `('GET', '/live', 200)`.
- Checks that `record.duration_ms` is at least `0`.
- Calls `json.dumps(record.__dict__, default=str)`.

Names used here:

- `json.dumps(x)` turns Python data into JSON text.

## Try it yourself

Run the domain tests.

```bash
.venv/bin/python -m pytest tests/unit/domain -q -p no:cacheprovider
```

You should see something like this:

```text
..................                                                       [100%]
18 passed in 0.01s
```

See how many unit tests pytest collects.

```bash
.venv/bin/python -m pytest tests/unit -q -p no:cacheprovider --collect-only | tail -3
```

You should see something like this:

```text
tests/unit/interfaces/test_http.py::test_every_request_is_logged_with_status_and_duration

59 tests collected in 2.49s
```

Run the unit and end-to-end tests with a coverage report.

```bash
.venv/bin/python -m pytest tests/unit tests/e2e -q -p no:cacheprovider --cov=secretless_app --cov-report=term | tail -8
```

You should see something like this:

```text
src/secretless_app/infrastructure/settings.py             51      1     18      1    97%   75
src/secretless_app/infrastructure/wiring.py               17      1      4      1    90%   21
src/secretless_app/interfaces/__init__.py                  0      0      0      0   100%
src/secretless_app/interfaces/http.py                     54      1      0      0    98%   49
src/secretless_app/interfaces/wsgi.py                     10     10      0      0     0%   3-17
--------------------------------------------------------------------------------------------------
TOTAL                                                    302     13     46      2    96%
63 passed in 109.52s (0:01:49)
```

## Mistakes people make

- Tests that depend on each other's order or leave files behind. Here every test gets its own temporary folder (`tmp_path`).
- Asserting too little: a test that only checks that nothing crashed. The test names here say the behavior they check.
- Sleeping in tests to wait for time to pass. The code takes a clock as an input and the tests use a fake clock, so no test waits.
- Chasing 100 percent coverage everywhere. This repository sets the bar where it matters (the domain and application layers) and reports the rest.
- Forgetting the marker on slow tests. Slow tests are marked and live in their own folder.

## Check yourself

1. **How does pytest know a function is a test?**
   Answer: Its name starts with `test_` and it is in a file called `test_*.py` under a folder listed in `testpaths`.

2. **What does a fixture give a test?**
   Answer: A prepared value (a temporary folder, a fake) that pytest creates and passes in by parameter name.

3. **What does `--strict-markers` do?**
   Answer: It turns a marker that is not declared in the configuration into an error.

4. **What does coverage measure?**
   Answer: Which lines and branches of the code ran while the tests ran.

5. **Why does this repository inject a clock instead of sleeping?**
   Answer: So tests are fast and give the same answer every time.

## Further reading

- pytest 9.1: https://docs.pytest.org/en/stable/
- pytest-cov 7.1: https://pytest-cov.readthedocs.io/en/latest/
- coverage.py 7.17: https://coverage.readthedocs.io/en/7.17.0/
