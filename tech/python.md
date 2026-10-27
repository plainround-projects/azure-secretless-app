# Python

*The language of the application and of its tests. Pinned here: Python 3.13.12 (the project requires 3.12 or newer).*

## What it is

Python is a programming language. You write instructions in text files that end in `.py`. A program called the **interpreter** reads the file and carries out the instructions one at a time. A **module** is one `.py` file. A **package** is a folder of modules with a name; other code gets things from it with `import`.

## Why this repository uses it

The lesson's starting point is a small Flask app in Python, so the whole application is Python. It is split into four **layers** (folders): `domain` (rules with no outside dependencies), `application` (what the app does, described against interfaces), `infrastructure` (the code that talks to Azure, the environment and the logs) and `interfaces` (the web routes). Reading the code well means knowing the handful of Python features it relies on, listed below at the place each is used.

## Where it appears

| File | What it does with it |
|---|---|
| `src/secretless_app/domain/` | Plain Python objects and rules: a blob name, a secret that never prints, named errors. |
| `src/secretless_app/application/` | The two use cases and the *ports* (interfaces) they need. |
| `src/secretless_app/infrastructure/` | Adapters to Azure, the environment settings, the JSON log format, the composition root. |
| `src/secretless_app/interfaces/` | The Flask routes and the gunicorn entry point. |
| `tests/` | Test functions run by pytest. |

## How it works underneath

You start a program with `python -m some.package.module`. The `-m` flag means "run this module by its package name". The interpreter finds the module, turns the text into an internal form called **bytecode**, and runs it from the top.

Everything is an **object**: numbers, text, functions, classes. A **variable** is a name that points at an object. A **function** is an object you can call. A **class** is a recipe for making objects.

Python does not check types before it runs. You can write **type hints** (`name: str`) to say what you expect. The interpreter ignores them while running. A separate tool, mypy (see `mypy.md`), reads them and finds mistakes without running the code.

The **standard library** is the set of modules that ship with Python (`logging`, `json`, `urllib`, `dataclasses`). Anything else has to be installed first (see `pip-uv-and-lock-files.md`) into a **virtual environment**: a private folder (`.venv/`) that holds the installed packages for one project, so projects do not disturb each other.

## Walkthrough of this repository's use

### A frozen dataclass: a small object with a rule

```python
_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
```

```python
@dataclass(frozen=True, slots=True)
class BlobName:
    """A blob name that is safe to use as a path segment: 1 to 128 characters, no slash, no dot-dot."""

    value: str

    def __post_init__(self) -> None:
        """Reject anything outside letters, digits, dot, underscore and hyphen, or any run of two dots."""
        if _PATTERN.fullmatch(self.value) is None or ".." in self.value:
            raise InvalidBlobNameError(
                "blob names use 1 to 128 letters, digits, dots, underscores or hyphens, "
                "start with a letter or digit and contain no '..'"
            )
```

`@dataclass` is a **decorator**: it rewrites the class under it. It writes `__init__`, `__repr__` and `==` from the field list (`value: str`). `frozen=True` forbids changing a field after the object exists, so a `BlobName` that passed the rule stays valid. `slots=True` stores fields in a fixed layout, which saves memory and rejects typos in attribute names. `__post_init__` runs right after `__init__`; if the text does not match the pattern, it raises an error, so a bad name can never be an object. The regular expression says: one letter or digit, then up to 127 letters, digits, dots, underscores or hyphens. The extra test `".." in self.value` rejects two dots in a row.

### A class that hides its value

```python
class Secret:
    """Holds a secret string; `repr`, `str` and formatting show a placeholder, `reveal` returns the value."""

    __slots__ = ("_value",)

    def __init__(self, value: str) -> None:
        """Wrap `value`."""
        self._value = value

    def reveal(self) -> str:
        """Return the secret itself; call it only where the value is used."""
        return self._value

    def __len__(self) -> int:
        """Return the length of the secret, which is safe to report."""
        return len(self._value)

    def __repr__(self) -> str:
        """Return a placeholder."""
        return "Secret(<redacted>)"

    __str__ = __repr__
```

`__slots__ = ("_value",)` allows exactly one attribute. `__repr__` and `__str__` are the methods Python calls when it prints an object or formats it into text; both return a placeholder, so a log line or an error message cannot leak the value. `__len__` lets `len(secret)` work. The only way out is the method `reveal()`.

### A Protocol: an interface without inheritance

```python
class SecretStore(Protocol):
    """Reads named secrets."""

    def get(self, name: str) -> Secret:
        """Return the current value of the secret `name`."""
        ...
```

`Protocol` (from `typing`) describes the methods an object must have. Any class with a matching `get` method counts as a `SecretStore`, without inheriting from it. The Azure adapter and the in-memory test double both qualify. The `...` is a body that does nothing. This is how the `application` layer depends on a *shape*, not on Azure.

### Union types, `Mapping` and class methods

```python
    def from_env(cls, env: Mapping[str, str]) -> "Settings":
        """Read and validate `env`; raise `ConfigError` naming every problem at once."""
        problems: list[str] = []
        backend = env.get("BACKEND", "azure")
        if backend not in BACKENDS:
            problems.append(f"BACKEND must be one of {BACKENDS}, got {backend!r}")
        vault_url = env.get("VAULT_URL") or None
```

`str | None` means "text or nothing" (Python 3.10 and newer syntax). `Mapping[str, str]` is any read-only dictionary, so tests can pass a plain dict instead of the real environment. `@classmethod` makes `from_env` a function that belongs to the class and receives the class as `cls`; it builds and returns a `Settings`. The string `"Settings"` as a return type is a **forward reference**: the class is not finished yet at that point.

### Named errors

```python
class UploadTooLargeError(SecretlessError):
    """The upload is bigger than the configured limit."""

    def __init__(self, size: int, limit: int) -> None:
        super().__init__(f"upload of {size} bytes exceeds the limit of {limit} bytes")
        self.size = size
        self.limit = limit
```

Each failure has its own class, so the web layer can choose a status code per kind of failure. `super().__init__(...)` calls the parent class to set the message. The attributes `size` and `limit` carry the facts.

### Comprehensions, f-strings and `with`

```python
        payload.update({key: value for key, value in vars(record).items() if key not in _RESERVED})
```

`{key: value for key, value in vars(record).items() if key not in _RESERVED}` is a **dictionary comprehension**: it builds a new dictionary from the log record's attributes, leaving out the built-in ones, so extra fields passed with `extra=` become top-level keys in the JSON line. An **f-string** such as `f"upload of {size} bytes exceeds the limit of {limit} bytes"` puts values into text. The tests use `with pytest.raises(...)`, a **context manager**: the block must raise that error or the test fails.

### Dependency injection by constructor

```python
@dataclass(frozen=True, slots=True)
class SaveUpload:
    """Validate the name and the size, then write the blob (overwriting a blob of the same name)."""

    blobs: BlobStore
    max_bytes: int

    def run(self, raw_name: str, data: bytes) -> BlobName:
        """Return the saved name; raise `InvalidBlobNameError`, `UploadTooLargeError` or `DependencyError`."""
        name = BlobName(raw_name)
        if len(data) > self.max_bytes:
            raise UploadTooLargeError(len(data), self.max_bytes)
        self.blobs.put(name, data)
        return name
```

`SaveUpload` does not create its storage. It is handed `blobs` (anything with a `put` method) and `max_bytes`. Tests pass an in-memory fake; production passes the Azure adapter. This is the single design idea that makes the app testable without Azure.

### Every line, in order

This part walks through every file this note is responsible for, from the first non-blank line to the last, in blocks. Each block shows the lines (the numbers say where they sit in the file) and then explains them. New ideas are explained at the first place they are needed; later blocks use them without repeating the explanation.

#### `src/secretless_app/__init__.py`

1 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""A web app that reaches Key Vault and Blob Storage with a managed identity and no stored secret."""
```

**New idea.** A **managed identity** is an identity that Azure creates and looks after for a workload, with no password to store or rotate. When the workload runs, it asks a local Azure endpoint for a token for that identity. A *user-assigned* identity exists on its own and can be attached to several resources; its *client id* names it when a program asks for a token and its *principal id* names it when roles are granted.

**New idea.** **Azure Key Vault** stores secrets, keys and certificates behind Azure's access control and writes an audit record of every use. A program reads a secret by calling the vault with its identity, so the secret never has to sit in a file or in the program's settings.

**New idea.** **Azure Blob Storage** stores files (*blobs*) in a *storage account*. Blobs live in *containers*, which work like top-level folders, and each blob is addressed by account, container and name. (This "container" is not a Docker container.)

**New idea.** A **module** is one `.py` file. Python runs a file from the top to the bottom, once, the first time something imports it; `def` and `class` statements at the top level just create functions and classes, they do not run their bodies.

**New idea.** A **docstring** is a text in triple quotes as the very first statement of a module, class or function. It does nothing when the program runs; tools and people read it as the official description.

The module docstring says: A web app that reaches Key Vault and Blob Storage with a managed identity and no stored secret.

#### `src/secretless_app/application/__init__.py`

1 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""Use cases and the ports they need; knows the domain, nothing about Azure or HTTP."""
```

**New idea.** A **port** is a number between 1 and 65535 that tells the computer which program on it should receive a network connection. An address such as `127.0.0.1:8000` means "this computer, port 8000"; `127.0.0.1` is the address a computer uses to talk to itself.

**New idea.** **HTTP** is the protocol of the web. A client sends a *request* (a method such as GET or POST, a path, headers and sometimes a body) and the server sends back a *response* with a three-digit **status code**: 200 means success, 201 created, 400 the request was bad, 403 forbidden, 404 not found, 413 too large, 502 a server behind this one failed.

The module docstring says: Use cases and the ports they need; knows the domain, nothing about Azure or HTTP.

#### `src/secretless_app/application/check_health.py`

12 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""The health check: proves the vault role works by reading the partner key."""
```

**New idea.** A **health check** is a small request that a platform sends to a running program to ask whether it is working. A *liveness* check that keeps failing makes the platform restart the program; a *readiness* check that fails keeps traffic away from it.

The module docstring says: The health check: proves the vault role works by reading the partner key.

**Line 3**

```python
from dataclasses import dataclass
```

What happens, step by step:

- `dataclass` from `dataclasses`: the decorator that turns a class into a data class.

**Lines 5 to 6**

```python
from secretless_app.application.ports import SecretStore
from secretless_app.domain.health import HealthReport
```

What happens, step by step:

- `SecretStore` from the repository's own module `secretless_app.application.ports`: Reads named secrets (defined in `src/secretless_app/application/ports.py`)
- `HealthReport` from the repository's own module `secretless_app.domain.health`: The vault answered: the secret exists and has `key_length` characters (defined in `src/secretless_app/domain/health.py`)

**Lines 9 to 14**

```python
@dataclass(frozen=True, slots=True)
class CheckHealth:
    """Read the partner key and report its length."""

    secrets: SecretStore
    secret_name: str
```

The docstring in the code says: Read the partner key and report its length.

**Class `CheckHealth`**.

**New idea.** `@dataclass` is a **decorator** (a line starting with `@` that wraps the class below it). It writes the boring methods for a class that mostly holds data: from the list of fields (`name: type`) it generates `__init__`, `__repr__` and `==`. With `frozen=True` an object cannot be changed after it is created; with `slots=True` the object stores only the listed fields, which saves memory and rejects typos in attribute names.

**New idea.** `class Name:` defines a **class**: a blueprint for objects that bundle data (attributes) with functions that work on it (methods). Calling the class, `Name(...)`, builds one object, an **instance**.

What the class declares:

- Decorator `@dataclass(frozen=True, slots=True)`.
- Declares the field `secrets` with type `SecretStore`.
- Declares the field `secret_name` with type `str`.

**Lines 16 to 18**

```python
    def run(self) -> HealthReport:
        """Return the report, or raise `DependencyError` (`AccessDeniedError` when the role is missing)."""
        return HealthReport(key_length=len(self.secrets.get(self.secret_name)))
```

The docstring in the code says: Return the report, or raise `DependencyError` (`AccessDeniedError` when the role is missing).

**Method `run`** takes no parameters; gives back `HealthReport`.

**New idea.** A **type hint** such as `name: str` or `-> int` says what kind of value a parameter or result is. Python does not enforce hints when the program runs; the checker `mypy` reads them before the program runs and reports mismatches.

**New idea.** Inside a method, the first parameter, by convention `self`, is the object the method was called on. `self.value` reads or sets an attribute of that object.

**New idea.** `def name(parameters):` defines a **function**: a named, reusable block of code. The indented lines under it are its body, which runs only when the function is **called** as `name(values)`. `return value` hands a result back to the caller; a function without `return` gives back `None`.

What happens, step by step:

- Returns `HealthReport(key_length=len(self.secrets.get(self.secret_name)))`.

Names used here:

- `len(x)` counts the items in `x`.

#### `src/secretless_app/application/ports.py`

14 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""What the use cases need from the outside world."""
```

The module docstring says: What the use cases need from the outside world.

**Line 3**

```python
from typing import Protocol
```

What happens, step by step:

- `Protocol` from `typing`: the base for describing an interface by its methods.

**Lines 5 to 6**

```python
from secretless_app.domain.blob_name import BlobName
from secretless_app.domain.secret import Secret
```

What happens, step by step:

- `BlobName` from the repository's own module `secretless_app.domain.blob_name`: A blob name that is safe to use as a path segment: 1 to 128 characters, no slash, no dot-dot (defined in `src/secretless_app/domain/blob_name.py`)
- `Secret` from the repository's own module `secretless_app.domain.secret`: Holds a secret string; `repr`, `str` and formatting show a placeholder, `reveal` returns the value (defined in `src/secretless_app/domain/secret.py`)

**Lines 9 to 10**

```python
class SecretStore(Protocol):
    """Reads named secrets."""
```

The docstring in the code says: Reads named secrets.

**Class `SecretStore`**, built on `Protocol`.

**New idea.** A `Protocol` (from `typing`) describes the methods an object must have, without inheritance. Any class that has methods with matching names and signatures counts as that protocol. The application layer uses protocols to depend on a *shape* and not on a concrete Azure class, so tests can pass a fake.

**Lines 12 to 14**

```python
    def get(self, name: str) -> Secret:
        """Return the current value of the secret `name`."""
        ...
```

The docstring in the code says: Return the current value of the secret `name`.

**Method `get`** takes `name` (type `str`); gives back `Secret`.

**New idea.** `...` (an **ellipsis**) is a placeholder body meaning "not written here"; in a protocol it means the method is only described, not implemented.

What happens, step by step:

- `...`: an empty body (nothing happens here).

**Lines 17 to 18**

```python
class BlobStore(Protocol):
    """Writes blobs into the uploads container."""
```

The docstring in the code says: Writes blobs into the uploads container.

**Class `BlobStore`**, built on `Protocol`.

**Lines 20 to 22**

```python
    def put(self, name: BlobName, data: bytes) -> None:
        """Create or overwrite the blob `name` with `data`."""
        ...
```

The docstring in the code says: Create or overwrite the blob `name` with `data`.

**Method `put`** takes `name` (type `BlobName`), `data` (type `bytes`); gives back `None`.

**New idea.** `None` is Python's value for "nothing here". Functions that find nothing return it, and a parameter that defaults to `None` means "not given".

What happens, step by step:

- `...`: an empty body (nothing happens here).

#### `src/secretless_app/application/save_upload.py`

17 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""The upload use case: proves the blob role works by writing a file."""
```

The module docstring says: The upload use case: proves the blob role works by writing a file.

**Line 3**

```python
from dataclasses import dataclass
```

What happens, step by step:

- `dataclass` from `dataclasses`: the decorator that turns a class into a data class.

**Lines 5 to 7**

```python
from secretless_app.application.ports import BlobStore
from secretless_app.domain.blob_name import BlobName
from secretless_app.domain.errors import UploadTooLargeError
```

What happens, step by step:

- `BlobStore` from the repository's own module `secretless_app.application.ports`: Writes blobs into the uploads container (defined in `src/secretless_app/application/ports.py`)
- `BlobName` from the repository's own module `secretless_app.domain.blob_name`: A blob name that is safe to use as a path segment: 1 to 128 characters, no slash, no dot-dot (defined in `src/secretless_app/domain/blob_name.py`)
- `UploadTooLargeError` from the repository's own module `secretless_app.domain.errors`: The upload is bigger than the configured limit (defined in `src/secretless_app/domain/errors.py`)

**Lines 10 to 15**

```python
@dataclass(frozen=True, slots=True)
class SaveUpload:
    """Validate the name and the size, then write the blob (overwriting a blob of the same name)."""

    blobs: BlobStore
    max_bytes: int
```

The docstring in the code says: Validate the name and the size, then write the blob (overwriting a blob of the same name).

**Class `SaveUpload`**.

What the class declares:

- Decorator `@dataclass(frozen=True, slots=True)`.
- Declares the field `blobs` with type `BlobStore`.
- Declares the field `max_bytes` with type `int`.

**Lines 17 to 23**

```python
    def run(self, raw_name: str, data: bytes) -> BlobName:
        """Return the saved name; raise `InvalidBlobNameError`, `UploadTooLargeError` or `DependencyError`."""
        name = BlobName(raw_name)
        if len(data) > self.max_bytes:
            raise UploadTooLargeError(len(data), self.max_bytes)
        self.blobs.put(name, data)
        return name
```

The docstring in the code says: Return the saved name; raise `InvalidBlobNameError`, `UploadTooLargeError` or `DependencyError`.

**Method `run`** takes `raw_name` (type `str`), `data` (type `bytes`); gives back `BlobName`.

**New idea.** `if condition:` runs its block only when the condition is true; `elif` adds another test; `else` is what runs when none matched.

**New idea.** `raise Error(...)` stops the current function and signals a failure. `raise NewError(...) from error` also records the original error as the cause, so the traceback shows both.

What happens, step by step:

- Sets `name` to the result of calling `BlobName(raw_name)`.
- If `len(data)` is greater than `self.max_bytes`:
  - Raises `UploadTooLargeError(len(data), self.max_bytes)`.
- Calls `self.blobs.put(name, data)`.
- Returns `name`.

#### `src/secretless_app/application/services.py`

9 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""The use cases the interfaces layer calls, bundled so the composition root can build them once."""
```

The module docstring says: The use cases the interfaces layer calls, bundled so the composition root can build them once.

**Line 3**

```python
from dataclasses import dataclass
```

What happens, step by step:

- `dataclass` from `dataclasses`: the decorator that turns a class into a data class.

**Lines 5 to 6**

```python
from secretless_app.application.check_health import CheckHealth
from secretless_app.application.save_upload import SaveUpload
```

What happens, step by step:

- `CheckHealth` from the repository's own module `secretless_app.application.check_health`: Read the partner key and report its length (defined in `src/secretless_app/application/check_health.py`)
- `SaveUpload` from the repository's own module `secretless_app.application.save_upload`: Validate the name and the size, then write the blob (overwriting a blob of the same name) (defined in `src/secretless_app/application/save_upload.py`)

**Lines 9 to 14**

```python
@dataclass(frozen=True, slots=True)
class Services:
    """Every use case of the app."""

    check_health: CheckHealth
    save_upload: SaveUpload
```

The docstring in the code says: Every use case of the app.

**Class `Services`**.

What the class declares:

- Decorator `@dataclass(frozen=True, slots=True)`.
- Declares the field `check_health` with type `CheckHealth`.
- Declares the field `save_upload` with type `SaveUpload`.

#### `src/secretless_app/domain/__init__.py`

1 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""Rules that need nothing outside the standard library: names, secrets, errors."""
```

The module docstring says: Rules that need nothing outside the standard library: names, secrets, errors.

#### `src/secretless_app/domain/blob_name.py`

16 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""The naming rule for uploaded blobs."""
```

The module docstring says: The naming rule for uploaded blobs.

**Lines 3 to 4**

```python
import re
from dataclasses import dataclass
```

What happens, step by step:

- `re`: the standard-library module for regular expressions.
- `dataclass` from `dataclasses`: the decorator that turns a class into a data class.

**Line 6**

```python
from secretless_app.domain.errors import InvalidBlobNameError
```

What happens, step by step:

- `InvalidBlobNameError` from the repository's own module `secretless_app.domain.errors`: The requested blob name breaks the naming rule (defined in `src/secretless_app/domain/errors.py`)

**Line 8**

```python
_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
```

**New idea.** A **regular expression** is a compact pattern for matching text: `[a-z]` is one lowercase letter, `+` means one or more, `^` and `$` mean start and end of the text, `{1,127}` means one to 127 repeats. `re.compile(pattern)` prepares it once.

What happens, step by step:

- Sets `_PATTERN` to the result of calling `re.compile('[A-Za-z0-9][A-Za-z0-9._-]{0,127}')`.

Names used here:

- `re.compile(pattern)` prepares a regular expression for repeated use.

**Lines 11 to 15**

```python
@dataclass(frozen=True, slots=True)
class BlobName:
    """A blob name that is safe to use as a path segment: 1 to 128 characters, no slash, no dot-dot."""

    value: str
```

The docstring in the code says: A blob name that is safe to use as a path segment: 1 to 128 characters, no slash, no dot-dot.

**Class `BlobName`**.

What the class declares:

- Decorator `@dataclass(frozen=True, slots=True)`.
- Declares the field `value` with type `str`.

**Lines 17 to 23**

```python
    def __post_init__(self) -> None:
        """Reject anything outside letters, digits, dot, underscore and hyphen, or any run of two dots."""
        if _PATTERN.fullmatch(self.value) is None or ".." in self.value:
            raise InvalidBlobNameError(
                "blob names use 1 to 128 letters, digits, dots, underscores or hyphens, "
                "start with a letter or digit and contain no '..'"
            )
```

The docstring in the code says: Reject anything outside letters, digits, dot, underscore and hyphen, or any run of two dots.

**Method `__post_init__`** takes no parameters; gives back `None`.

**New idea.** `__post_init__` is a dataclass hook that runs right after the generated `__init__`. It is the natural place to check that the fields are valid and to raise an error if not.

**New idea.** `and` is true when both sides are; `or` is true when either is, and it stops at the first true side. `not` flips true and false.

**New idea.** `x is None` tests whether `x` is exactly the object `None` (identity), as opposed to `==`, which tests equal value.

**New idea.** `a in b` is true when `a` is one of the items of `b` (or a piece of the text `b`).

What happens, step by step:

- If `_PATTERN.fullmatch(self.value)` is exactly `None` **or** `'..'` is one of / is inside `self.value`:
  - Raises `InvalidBlobNameError` with `"blob names use 1 to 128 letters, digits, dots, underscores or hyphens, start with a letter or digit and cont…` (long; see the quote).

Names used here:

- `.fullmatch(text)` is true when the whole text fits the pattern.

#### `src/secretless_app/domain/errors.py`

20 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""Named errors. The interfaces layer maps each one to an HTTP status."""
```

The module docstring says: Named errors. The interfaces layer maps each one to an HTTP status.

**Lines 4 to 5**

```python
class SecretlessError(Exception):
    """Base class for every error this application raises on purpose."""
```

The docstring in the code says: Base class for every error this application raises on purpose.

**Class `SecretlessError`**, built on `Exception`.

**New idea.** Classes that inherit from `Exception` are **errors**. `raise MyError(...)` stops the current code and hands the error up to whatever called it, until some `try`/`except` catches it. Giving each failure its own class lets the caller react differently to different failures.

**Lines 8 to 9**

```python
class InvalidBlobNameError(SecretlessError):
    """The requested blob name breaks the naming rule."""
```

The docstring in the code says: The requested blob name breaks the naming rule.

**Class `InvalidBlobNameError`**, built on `SecretlessError`.

**Lines 12 to 13**

```python
class UploadTooLargeError(SecretlessError):
    """The upload is bigger than the configured limit."""
```

The docstring in the code says: The upload is bigger than the configured limit.

**Class `UploadTooLargeError`**, built on `SecretlessError`.

**Lines 15 to 18**

```python
    def __init__(self, size: int, limit: int) -> None:
        super().__init__(f"upload of {size} bytes exceeds the limit of {limit} bytes")
        self.size = size
        self.limit = limit
```

**Method `__init__`** takes `size` (type `int`), `limit` (type `int`); gives back `None`.

**New idea.** `__init__` is the special method Python calls right after it creates an object; it sets the object's starting attributes. Names with double underscores on both sides are **dunder methods**: Python calls them for you in response to syntax (`__init__` on creation, `__repr__` when printing, `__len__` for `len(x)`, `__eq__` for `==`).

**New idea.** An **f-string** is text written `f"...{value}..."`: whatever is inside the braces is evaluated and its text is put into the string. A format after a colon controls how: `{x:g}` prints a number without trailing zeros, `{x:.1f}` keeps one decimal, `{x!r}` uses the value's `repr`.

What happens, step by step:

- Calls `super().__init__(f'upload of {size} bytes exceeds the limit of {limit} bytes')`.
- Sets `self.size` to `size`.
- Sets `self.limit` to `limit`.

Names used here:

- `super()` reaches the parent class's version of a method.

**Lines 21 to 22**

```python
class DependencyError(SecretlessError):
    """An Azure service could not be used; `code` is the service's own error code."""
```

The docstring in the code says: An Azure service could not be used; `code` is the service's own error code.

**Class `DependencyError`**, built on `SecretlessError`.

**Lines 24 to 28**

```python
    def __init__(self, service: str, code: str, detail: str) -> None:
        super().__init__(f"{service}: {code}: {detail}")
        self.service = service
        self.code = code
        self.detail = detail
```

**Method `__init__`** takes `service` (type `str`), `code` (type `str`), `detail` (type `str`); gives back `None`.

What happens, step by step:

- Calls `super().__init__(f'{service}: {code}: {detail}')`.
- Sets `self.service` to `service`.
- Sets `self.code` to `code`.
- Sets `self.detail` to `detail`.

**Lines 31 to 32**

```python
class AccessDeniedError(DependencyError):
    """The app's identity is known to the service but holds no role that allows the call."""
```

The docstring in the code says: The app's identity is known to the service but holds no role that allows the call.

**Class `AccessDeniedError`**, built on `DependencyError`.

#### `src/secretless_app/domain/health.py`

6 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""What a successful health check reports."""
```

The module docstring says: What a successful health check reports.

**Line 3**

```python
from dataclasses import dataclass
```

What happens, step by step:

- `dataclass` from `dataclasses`: the decorator that turns a class into a data class.

**Lines 6 to 10**

```python
@dataclass(frozen=True, slots=True)
class HealthReport:
    """The vault answered: the secret exists and has `key_length` characters. The key itself is never reported."""

    key_length: int
```

The docstring in the code says: The vault answered: the secret exists and has `key_length` characters. The key itself is never reported.

**Class `HealthReport`**.

What the class declares:

- Decorator `@dataclass(frozen=True, slots=True)`.
- Declares the field `key_length` with type `int`.

#### `src/secretless_app/domain/secret.py`

17 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""A secret value that cannot be printed or logged by accident."""
```

The module docstring says: A secret value that cannot be printed or logged by accident.

**Lines 4 to 7**

```python
class Secret:
    """Holds a secret string; `repr`, `str` and formatting show a placeholder, `reveal` returns the value."""

    __slots__ = ("_value",)
```

The docstring in the code says: Holds a secret string; `repr`, `str` and formatting show a placeholder, `reveal` returns the value.

**Class `Secret`**.

**New idea.** A **tuple** `(a, b)` is a fixed list of values. **Unpacking** `x, y = pair` assigns the parts to separate names in one statement.

**New idea.** `__slots__ = ("a",)` limits an object to exactly those attributes, which saves memory and turns attribute typos into errors.

What the class declares:

- Sets `__slots__` to `('_value',)`.

**Lines 9 to 11**

```python
    def __init__(self, value: str) -> None:
        """Wrap `value`."""
        self._value = value
```

The docstring in the code says: Wrap `value`.

**Method `__init__`** takes `value` (type `str`); gives back `None`.

What happens, step by step:

- Sets `self._value` to `value`.

**Lines 13 to 15**

```python
    def reveal(self) -> str:
        """Return the secret itself; call it only where the value is used."""
        return self._value
```

The docstring in the code says: Return the secret itself; call it only where the value is used.

**Method `reveal`** takes no parameters; gives back `str`.

What happens, step by step:

- Returns `self._value`.

**Lines 17 to 19**

```python
    def __len__(self) -> int:
        """Return the length of the secret, which is safe to report."""
        return len(self._value)
```

The docstring in the code says: Return the length of the secret, which is safe to report.

**Method `__len__`** takes no parameters; gives back `int`.

What happens, step by step:

- Returns `len(self._value)`.

**Lines 21 to 23**

```python
    def __repr__(self) -> str:
        """Return a placeholder."""
        return "Secret(<redacted>)"
```

The docstring in the code says: Return a placeholder.

**Method `__repr__`** takes no parameters; gives back `str`.

What happens, step by step:

- Returns `'Secret(<redacted>)'`.

**Line 25**

```python
    __str__ = __repr__
```

What happens, step by step:

- Sets `__str__` to `__repr__`.

#### `src/secretless_app/infrastructure/__init__.py`

1 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""Adapters to Azure, the environment and the process: everything with a side effect."""
```

**New idea.** An **environment variable** is a named text value that the operating system hands to every program it starts, such as `PORT=8080`. It is the usual way to configure a program without changing its code, and the way a deployment passes settings that differ between machines.

The module docstring says: Adapters to Azure, the environment and the process: everything with a side effect.

#### `src/secretless_app/infrastructure/azure_errors.py`

35 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""Turn Azure SDK exceptions into the application's named errors."""
```

**New idea.** An **SDK** (software development kit) or *client library* is a package of ready-made code that talks to a service for you. The Azure ones turn calls such as "read this secret" into the correct web requests, add the access token and retry transient failures.

The module docstring says: Turn Azure SDK exceptions into the application's named errors.

**Lines 3 to 8**

```python
from azure.core.exceptions import (
    ClientAuthenticationError,
    HttpResponseError,
    ServiceRequestError,
    ServiceResponseError,
)
```

**New idea.** **DNS** (the Domain Name System) is the network's telephone book: it turns a name such as `myvault.vault.azure.net` into the IP address a computer connects to. Asking it is called *resolving* the name, and the answer depends on which network and which name server you ask.

What happens, step by step:

- `ClientAuthenticationError` from `azure.core.exceptions`: raised when Azure refuses the credential.
- `HttpResponseError` from `azure.core.exceptions`: raised for any HTTP error reply; `.status_code` holds the number.
- `ServiceRequestError` from `azure.core.exceptions`: raised when a request could not be sent (network or DNS failure).
- `ServiceResponseError` from `azure.core.exceptions`: raised when a response could not be read.

**Line 10**

```python
from secretless_app.domain.errors import AccessDeniedError, DependencyError, SecretlessError
```

What happens, step by step:

- `AccessDeniedError` from the repository's own module `secretless_app.domain.errors`: The app's identity is known to the service but holds no role that allows the call (defined in `src/secretless_app/domain/errors.py`)
- `DependencyError` from the repository's own module `secretless_app.domain.errors`: An Azure service could not be used; `code` is the service's own error code (defined in `src/secretless_app/domain/errors.py`)
- `SecretlessError` from the repository's own module `secretless_app.domain.errors`: Base class for every error this application raises on purpose (defined in `src/secretless_app/domain/errors.py`)

**Line 12**

```python
_DETAIL_LIMIT = 2000
```

What happens, step by step:

- Sets `_DETAIL_LIMIT` to `2000`.

**Lines 15 to 31**

```python
def translate(service: str, error: Exception) -> SecretlessError:
    """Return `AccessDeniedError` for HTTP 403, `DependencyError` for everything else.

    The detail keeps the SDK's message because it names the caller's object id and the denied action,
    which is what step 5 of the lesson reads in the logs. It never holds a secret value.
    """
    detail = str(error)[:_DETAIL_LIMIT]
    if isinstance(error, ClientAuthenticationError):
        return DependencyError(service, "AuthenticationFailed", detail)
    if isinstance(error, HttpResponseError):
        code = _error_code(error)
        if error.status_code == 403:
            return AccessDeniedError(service, code, detail)
        return DependencyError(service, code, detail)
    if isinstance(error, ServiceRequestError | ServiceResponseError):
        return DependencyError(service, "Unreachable", detail)
    raise error
```

**New idea.** **Microsoft Entra ID** (formerly Azure Active Directory) is the identity service of Azure. A **tenant** is one organization's directory in it. Every identity in the directory (a person, a group, an application, a managed identity) has an *object id*, and the party that receives permissions is called the *principal*.

The docstring in the code says: Return `AccessDeniedError` for HTTP 403, `DependencyError` for everything else. The detail keeps the SDK's message because it names the caller's object id and the denied action, which is what step 5 of the lesson reads in the logs. It never holds a secret value.

**Function `translate`** takes `service` (type `str`), `error` (type `Exception`); gives back `SecretlessError`.

**New idea.** `items[1:3]` is a **slice**: the elements from position 1 up to (not including) 3. Positions start at 0, and a negative position counts from the end.

**New idea.** `A | B` in a type hint means "either an A or a B". `str | None` means "text, or nothing at all".

What happens, step by step:

- Sets `detail` to `str(error)[:_DETAIL_LIMIT]`.
- If `isinstance(error, ClientAuthenticationError)` is true:
  - Returns `DependencyError(service, 'AuthenticationFailed', detail)`.
- If `isinstance(error, HttpResponseError)` is true:
  - Sets `code` to the result of calling `_error_code(error)`.
  - If `error.status_code` equals `403`:
    - Returns `AccessDeniedError(service, code, detail)`.
  - Returns `DependencyError(service, code, detail)`.
- If `isinstance(error, ServiceRequestError | ServiceResponseError)` is true:
  - Returns `DependencyError(service, 'Unreachable', detail)`.
- Raises `error`.

Names used here:

- `str(x)` turns a value into text.
- `isinstance(x, T)` is true when `x` is a `T` (or a subclass of it).

**Lines 34 to 43**

```python
def _error_code(error: HttpResponseError) -> str:
    """Prefer the most specific code: Key Vault inner `ForbiddenByRbac`, Storage `error_code`, then the generic one."""
    inner = getattr(error.error, "innererror", None)
    if isinstance(inner, dict) and inner.get("code"):
        return str(inner["code"])
    storage_code = getattr(error, "error_code", None)
    if storage_code is not None:
        return str(getattr(storage_code, "value", storage_code))
    generic = getattr(error.error, "code", None)
    return str(generic or error.reason or "Unknown")
```

The docstring in the code says: Prefer the most specific code: Key Vault inner `ForbiddenByRbac`, Storage `error_code`, then the generic one.

**Function `_error_code`** takes `error` (type `HttpResponseError`); gives back `str`.

What happens, step by step:

- Sets `inner` to the result of calling `getattr(error.error, 'innererror', None)`.
- If `isinstance(inner, dict)` is true **and** `inner.get('code')` is true:
  - Returns `str(inner['code'])`.
- Sets `storage_code` to the result of calling `getattr(error, 'error_code', None)`.
- If `storage_code` is not exactly `None`:
  - Returns `str(getattr(storage_code, 'value', storage_code))`.
- Sets `generic` to the result of calling `getattr(error.error, 'code', None)`.
- Returns `str(generic or error.reason or 'Unknown')`.

Names used here:

- `getattr(obj, "name", default)` reads the attribute whose name is given as text.

#### `src/secretless_app/infrastructure/logging.py`

29 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""One JSON object per log line on stdout, so Log Analytics can parse every field."""
```

**New idea.** Every program has **standard output** (its normal results) and **standard error** (its problem reports), two separate streams. Keeping them apart lets a caller capture the results while still seeing the errors.

**New idea.** **Log Analytics** is Azure's store for logs and metrics, queried with the Kusto Query Language (KQL). A *diagnostic setting* tells a resource to send its logs there, so that, for example, every refused request to a vault can be found afterwards.

The module docstring says: One JSON object per log line on stdout, so Log Analytics can parse every field.

**Lines 3 to 7**

```python
import json
import logging
import sys
from datetime import UTC, datetime
from typing import Any
```

What happens, step by step:

- `json`: the standard-library module for JSON.
- `logging`: the standard-library module for log records.
- `sys`: the standard-library module for the running interpreter (arguments, exit, streams).
- `UTC` from `datetime`: the UTC time zone.
- `datetime` from `datetime`: the date-and-time class.
- `Any` from `typing`: the type hint that allows any value.

**Line 9**

```python
_RESERVED = set(vars(logging.makeLogRecord({})))
```

**New idea.** A **dictionary** `{key: value}` looks values up by key: `d[key]` reads one, `d.get(key)` reads one and returns `None` if missing.

What happens, step by step:

- Sets `_RESERVED` to the result of calling `set(vars(logging.makeLogRecord({})))`.

Names used here:

- `set(x)` builds a set: a collection with no duplicates.

**Lines 12 to 13**

```python
class JsonFormatter(logging.Formatter):
    """Render a record as JSON; fields passed through `extra=` become top-level keys."""
```

The docstring in the code says: Render a record as JSON; fields passed through `extra=` become top-level keys.

**Class `JsonFormatter`**, built on `logging.Formatter`.

**New idea.** `class Child(Parent):` makes `Child` **inherit** from `Parent`: it starts with all of the parent's attributes and methods and can add to or replace them. `super()` reaches the parent's version of a method.

**Lines 15 to 26**

```python
    def format(self, record: logging.LogRecord) -> str:
        """Return the JSON line for `record`."""
        payload: dict[str, Any] = {
            "ts": datetime.fromtimestamp(record.created, UTC).isoformat(timespec="milliseconds"),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        payload.update({key: value for key, value in vars(record).items() if key not in _RESERVED})
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)
```

The docstring in the code says: Return the JSON line for `record`.

**Method `format`** takes `record` (type `logging.LogRecord`); gives back `str`.

**New idea.** Square brackets after a type, as in `list[str]` or `dict[str, int]`, say what the container holds: a list of text, or a dictionary from text to whole numbers.

**New idea.** **JSON** is a text format for data: objects `{"key": value}`, arrays `[1, 2]`, strings, numbers, `true`, `false` and `null`. `json.dumps(x)` turns Python data into JSON text and `json.loads(text)` turns JSON text back into Python data.

**New idea.** A **comprehension** builds a list, set or dictionary in one expression: `[f(x) for x in things if keep(x)]` means "for each `x` in `things` that passes `keep`, take `f(x)`". With braces and `key: value` it builds a dictionary.

What happens, step by step:

- Sets `payload` with type `dict[str, Any]` and starting value `{'ts': datetime.fromtimestamp(record.created, UTC).isoformat(timespec='milliseconds'), 'level': record.leveln…` (long; see the quote).
- Calls `payload.update({key: value for key, value in vars(record).items() if key not in _RESERVED})`.
- If `record.exc_info` is true:
  - Sets `payload['exc']` to the result of calling `self.formatException(record.exc_info)`.
- Returns `json.dumps(payload, default=str)`.

Names used here:

- `.isoformat()` formats a date-time as `2026-10-27T12:00:00+00:00`.
- `record.getMessage()` is the final log text with its placeholders filled in.
- `.update(other)` copies the entries of `other` into a dictionary.
- `.items()` on a dictionary lists its `(key, value)` pairs.
- `json.dumps(x)` turns Python data into JSON text.

**Lines 29 to 36**

```python
def configure_logging(level: str) -> None:
    """Send the root logger to stdout as JSON at `level`; calling it twice does not duplicate lines."""
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(level)
    logging.getLogger("azure").setLevel(logging.WARNING)  # the SDK logs every request header at INFO
```

The docstring in the code says: Send the root logger to stdout as JSON at `level`; calling it twice does not duplicate lines.

**Function `configure_logging`** takes `level` (type `str`); gives back `None`.

**New idea.** `logging.getLogger("name")` returns the logger with that name. Code writes records with `.info`, `.warning`, `.error`; handlers decide where the records go and in what format.

What happens, step by step:

- Sets `handler` to the result of calling `logging.StreamHandler(sys.stdout)`.
- Calls `handler.setFormatter(JsonFormatter())`.
- Sets `root` to the result of calling `logging.getLogger()`.
- Sets `root.handlers[:]` to `[handler]`.
- Calls `root.setLevel(level)`.
- Calls `logging.getLogger('azure').setLevel(logging.WARNING)`.

Names used here:

- `logging.StreamHandler(stream)` is a handler that writes records to a stream such as standard output.
- `.setFormatter(f)` sets how a handler formats each record.
- `logging.getLogger(name)` returns the named logger.
- `.setLevel(level)` sets the lowest level a logger or handler lets through.

#### `src/secretless_app/infrastructure/memory_adapters.py`

38 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 5**

```python
"""In-memory stand-ins for Key Vault and Blob Storage.

They serve the unit tests and `BACKEND=memory`, which lets a reader run the app and rehearse the denial of
step 5 (`MEMORY_DENY=blob`) without a subscription.
"""
```

**New idea.** An Azure **subscription** is the billing container for resources: everything created in it is charged to it, and its settings and access control apply to it. A *tenant* (the organization's identity directory) can hold several subscriptions.

The module docstring says: In-memory stand-ins for Key Vault and Blob Storage. They serve the unit tests and `BACKEND=memory`, which lets a reader run the app and rehearse the denial of step 5 (`MEMORY_DENY=blob`) without a subscription.

**Lines 7 to 9**

```python
from secretless_app.domain.blob_name import BlobName
from secretless_app.domain.errors import AccessDeniedError, DependencyError
from secretless_app.domain.secret import Secret
```

What happens, step by step:

- `BlobName` from the repository's own module `secretless_app.domain.blob_name`: A blob name that is safe to use as a path segment: 1 to 128 characters, no slash, no dot-dot (defined in `src/secretless_app/domain/blob_name.py`)
- `AccessDeniedError` from the repository's own module `secretless_app.domain.errors`: The app's identity is known to the service but holds no role that allows the call (defined in `src/secretless_app/domain/errors.py`)
- `DependencyError` from the repository's own module `secretless_app.domain.errors`: An Azure service could not be used; `code` is the service's own error code (defined in `src/secretless_app/domain/errors.py`)
- `Secret` from the repository's own module `secretless_app.domain.secret`: Holds a secret string; `repr`, `str` and formatting show a placeholder, `reveal` returns the value (defined in `src/secretless_app/domain/secret.py`)

**Line 11**

```python
DEMO_SECRET_VALUE = "demo-value-123"
```

What happens, step by step:

- Sets `DEMO_SECRET_VALUE` to `'demo-value-123'`.

**Lines 14 to 15**

```python
class InMemorySecretStore:
    """A dictionary of secrets that can pretend the Secrets User role was removed."""
```

**New idea.** **Azure role-based access control (RBAC)** decides who may do what. A *role* is a named bundle of permissions (for example "Key Vault Secrets User" may read secrets), a *scope* is where the grant applies (one resource, a resource group, a whole subscription), and a *role assignment* connects an identity, a role and a scope. The smaller the scope, the less a leaked identity can do.

The docstring in the code says: A dictionary of secrets that can pretend the Secrets User role was removed.

**Class `InMemorySecretStore`**.

**Lines 17 to 20**

```python
    def __init__(self, secrets: dict[str, str], denied: bool = False) -> None:
        """Hold `secrets`; with `denied` every read raises `AccessDeniedError` as the vault does."""
        self._secrets = dict(secrets)
        self._denied = denied
```

The docstring in the code says: Hold `secrets`; with `denied` every read raises `AccessDeniedError` as the vault does.

**Method `__init__`** takes `secrets` (type `dict[str, str]`), `denied` (type `bool`), default `False`; gives back `None`.

**New idea.** A parameter written `name=value` has a **default**: if the caller leaves it out, the default is used.

What happens, step by step:

- Sets `self._secrets` to the result of calling `dict(secrets)`.
- Sets `self._denied` to `denied`.

Names used here:

- `dict(...)` builds a dictionary.

**Lines 22 to 30**

```python
    def get(self, name: str) -> Secret:
        """Return the secret `name`."""
        if self._denied:
            raise AccessDeniedError(
                "keyvault", "ForbiddenByRbac", "Caller is not authorized to perform action on resource."
            )
        if name not in self._secrets:
            raise DependencyError("keyvault", "SecretNotFound", f"secret {name!r} does not exist")
        return Secret(self._secrets[name])
```

The docstring in the code says: Return the secret `name`.

**Method `get`** takes `name` (type `str`); gives back `Secret`.

What happens, step by step:

- If `self._denied` is true:
  - Raises `AccessDeniedError` with `'keyvault'`; `'ForbiddenByRbac'`; `'Caller is not authorized to perform action on resource.'`.
- If `name` is not inside `self._secrets`:
  - Raises `DependencyError('keyvault', 'SecretNotFound', f'secret {name!r} does not exist')`.
- Returns `Secret(self._secrets[name])`.

**Lines 33 to 34**

```python
class InMemoryBlobStore:
    """A dictionary of blobs that can pretend the Blob Data Contributor role was removed."""
```

The docstring in the code says: A dictionary of blobs that can pretend the Blob Data Contributor role was removed.

**Class `InMemoryBlobStore`**.

**Lines 36 to 39**

```python
    def __init__(self, denied: bool = False) -> None:
        """Start empty; with `denied` every write raises `AccessDeniedError` as Storage does."""
        self.blobs: dict[str, bytes] = {}
        self._denied = denied
```

The docstring in the code says: Start empty; with `denied` every write raises `AccessDeniedError` as Storage does.

**Method `__init__`** takes `denied` (type `bool`), default `False`; gives back `None`.

What happens, step by step:

- Sets `self.blobs` with type `dict[str, bytes]` and starting value `{}`.
- Sets `self._denied` to `denied`.

**Lines 41 to 49**

```python
    def put(self, name: BlobName, data: bytes) -> None:
        """Create or overwrite the blob."""
        if self._denied:
            raise AccessDeniedError(
                "blob",
                "AuthorizationPermissionMismatch",
                "This request is not authorized to perform this operation using this permission.",
            )
        self.blobs[name.value] = data
```

The docstring in the code says: Create or overwrite the blob.

**Method `put`** takes `name` (type `BlobName`), `data` (type `bytes`); gives back `None`.

What happens, step by step:

- If `self._denied` is true:
  - Raises `AccessDeniedError` with `'blob'`; `'AuthorizationPermissionMismatch'`; `'This request is not authorized to perform this operation using this permission.'`.
- Sets `self.blobs[name.value]` to `data`.

#### `src/secretless_app/infrastructure/settings.py`

65 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""Configuration from the environment (twelve-factor), validated once at start-up."""
```

The module docstring says: Configuration from the environment (twelve-factor), validated once at start-up.

**Lines 3 to 5**

```python
from collections.abc import Mapping
from dataclasses import dataclass
from urllib.parse import urlparse
```

**New idea.** A **URL** is the full address of something on the web, such as `https://example.com:8443/path?x=1`: the protocol, the host name, an optional port, the path and an optional query.

What happens, step by step:

- `Mapping` from `collections.abc`: the type hint for a read-only dictionary.
- `dataclass` from `dataclasses`: the decorator that turns a class into a data class.
- `urlparse` from `urllib.parse`: splits a URL into its scheme, host, path, query and fragment.

**Lines 7 to 9**

```python
BACKENDS = ("azure", "memory")
DENIABLE = ("vault", "blob")
_LOG_LEVELS = ("DEBUG", "INFO", "WARNING", "ERROR")
```

What happens, step by step:

- Sets `BACKENDS` to `('azure', 'memory')`.
- Sets `DENIABLE` to `('vault', 'blob')`.
- Sets `_LOG_LEVELS` to `('DEBUG', 'INFO', 'WARNING', 'ERROR')`.

**Lines 12 to 13**

```python
class ConfigError(ValueError):
    """One or more settings are missing or malformed; the message lists all of them."""
```

The docstring in the code says: One or more settings are missing or malformed; the message lists all of them.

**Class `ConfigError`**, built on `ValueError`.

**Lines 16 to 28**

```python
@dataclass(frozen=True, slots=True)
class Settings:
    """Everything the app reads from the environment. None of it is a secret."""

    backend: str
    vault_url: str | None
    storage_url: str | None
    client_id: str | None
    container: str
    secret_name: str
    max_upload_bytes: int
    log_level: str
    memory_deny: frozenset[str]
```

**New idea.** Terraform's **state** is a file in which it records the real resources it created and their ids. Each run compares the code, the state and reality to decide what to change. It may contain sensitive values, so it is never committed; a *backend* is the place where the state is stored.

The docstring in the code says: Everything the app reads from the environment. None of it is a secret.

**Class `Settings`**.

What the class declares:

- Decorator `@dataclass(frozen=True, slots=True)`.
- Declares the field `backend` with type `str`.
- Declares the field `vault_url` with type `str | None`.
- Declares the field `storage_url` with type `str | None`.
- Declares the field `client_id` with type `str | None`.
- Declares the field `container` with type `str`.
- Declares the field `secret_name` with type `str`.
- Declares the field `max_upload_bytes` with type `int`.
- Declares the field `log_level` with type `str`.
- Declares the field `memory_deny` with type `frozenset[str]`.

**Lines 30 to 32**

```python
    @classmethod
    def from_env(cls, env: Mapping[str, str]) -> "Settings":
        """Read and validate `env`; raise `ConfigError` naming every problem at once."""
```

The docstring in the code says: Read and validate `env`; raise `ConfigError` naming every problem at once.

**Method `from_env`** takes `env` (type `Mapping[str, str]`); gives back `'Settings'`.

**New idea.** `@classmethod` makes a method that belongs to the class itself: its first parameter, `cls`, is the class, so the method can build and return a new instance.

The body is split into the parts below.

- Decorator `@classmethod`.

**Lines 33 to 51**

```python
        problems: list[str] = []
        backend = env.get("BACKEND", "azure")
        if backend not in BACKENDS:
            problems.append(f"BACKEND must be one of {BACKENDS}, got {backend!r}")
        vault_url = env.get("VAULT_URL") or None
        storage_url = env.get("STORAGE_URL") or None
        if backend == "azure":
            for name, value in (("VAULT_URL", vault_url), ("STORAGE_URL", storage_url)):
                if value is None or not _is_https_url(value):
                    problems.append(f"{name} must be an https URL when BACKEND=azure")
        max_upload_bytes = _positive_int(env, "MAX_UPLOAD_BYTES", 5_000_000, problems)
        log_level = env.get("LOG_LEVEL", "INFO").upper()
        if log_level not in _LOG_LEVELS:
            problems.append(f"LOG_LEVEL must be one of {_LOG_LEVELS}, got {log_level!r}")
        memory_deny = frozenset(part for part in env.get("MEMORY_DENY", "").split(",") if part)
        if not memory_deny <= set(DENIABLE):
            problems.append(f"MEMORY_DENY may only contain {DENIABLE}, got {sorted(memory_deny)}")
        if problems:
            raise ConfigError("; ".join(problems))
```

**New idea.** `for item in things:` runs its block once for each element of `things`, with `item` set to that element.

**New idea.** A **generator expression** `(f(x) for x in things)` produces its values one at a time as they are asked for, instead of building the whole list first.

What happens, step by step:

- Sets `problems` with type `list[str]` and starting value `[]`.
- Sets `backend` to the result of calling `env.get('BACKEND', 'azure')`.
- If `backend` is not inside `BACKENDS`:
  - Calls `problems.append(f'BACKEND must be one of {BACKENDS}, got {backend!r}')`.
- Sets `vault_url` to `env.get('VAULT_URL') or None`.
- Sets `storage_url` to `env.get('STORAGE_URL') or None`.
- If `backend` equals `'azure'`:
  - For each `(name, value)` in `(('VAULT_URL', vault_url), ('STORAGE_URL', storage_url))`:
    - If `value` is exactly `None` **or** it is not the case that `_is_https_url(value)` is true:
      - Calls `problems.append(f'{name} must be an https URL when BACKEND=azure')`.
- Sets `max_upload_bytes` to the result of calling `_positive_int(env, 'MAX_UPLOAD_BYTES', 5000000, problems)`.
- Sets `log_level` to the result of calling `env.get('LOG_LEVEL', 'INFO').upper()`.
- If `log_level` is not inside `_LOG_LEVELS`:
  - Calls `problems.append(f'LOG_LEVEL must be one of {_LOG_LEVELS}, got {log_level!r}')`.
- Sets `memory_deny` to the result of calling `frozenset((part for part in env.get('MEMORY_DENY', '').split(',') if part))`.
- If it is not the case that `memory_deny` is at most `set(DENIABLE)`:
  - Calls `problems.append(f'MEMORY_DENY may only contain {DENIABLE}, got {sorted(memory_deny)}')`.
- If `problems` is true:
  - Raises `ConfigError('; '.join(problems))`.

Names used here:

- `.append(x)` adds `x` to the end of a list.
- `.upper()` converts text to uppercase.
- `frozenset(x)` builds a set that cannot be changed.
- `.split(sep)` cuts text into a list of pieces at each `sep`.
- `sorted(x)` returns a new list with the items in order.
- `"sep".join(items)` glues text pieces together with `sep` between them.

**Lines 52 to 62**

```python
        return cls(
            backend=backend,
            vault_url=vault_url,
            storage_url=storage_url,
            client_id=env.get("AZURE_CLIENT_ID") or None,
            container=env.get("UPLOAD_CONTAINER", "uploads"),
            secret_name=env.get("SECRET_NAME", "partner-api-key"),
            max_upload_bytes=max_upload_bytes,
            log_level=log_level,
            memory_deny=memory_deny,
        )
```

What happens, step by step:

- Returns `cls(backend=backend, vault_url=vault_url, storage_url=storage_url, client_id=env.get('AZURE_CLIENT_ID') or No…` (long; see the quote).

**Lines 65 to 67**

```python
def _is_https_url(value: str) -> bool:
    parsed = urlparse(value)
    return parsed.scheme == "https" and bool(parsed.netloc)
```

**Function `_is_https_url`** takes `value` (type `str`); gives back `bool`.

What happens, step by step:

- Sets `parsed` to the result of calling `urlparse(value)`.
- Returns `parsed.scheme == 'https' and bool(parsed.netloc)`.

Names used here:

- `bool(x)` turns a value into `True` or `False`; empty text, `0`, `None` and empty containers are false.

**Lines 70 to 77**

```python
def _positive_int(env: Mapping[str, str], name: str, default: int, problems: list[str]) -> int:
    raw = env.get(name)
    if raw is None:
        return default
    if raw.isdecimal() and int(raw) > 0:
        return int(raw)
    problems.append(f"{name} must be a positive integer, got {raw!r}")
    return default
```

**Function `_positive_int`** takes `env` (type `Mapping[str, str]`), `name` (type `str`), `default` (type `int`), `problems` (type `list[str]`); gives back `int`.

What happens, step by step:

- Sets `raw` to the result of calling `env.get(name)`.
- If `raw` is exactly `None`:
  - Returns `default`.
- If `raw.isdecimal()` is true **and** `int(raw)` is greater than `0`:
  - Returns `int(raw)`.
- Calls `problems.append(f'{name} must be a positive integer, got {raw!r}')`.
- Returns `default`.

Names used here:

- `int(x)` turns a value into a whole number.

#### `src/secretless_app/infrastructure/wiring.py`

25 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""The composition root: build the use cases around the adapters the settings select."""
```

The module docstring says: The composition root: build the use cases around the adapters the settings select.

**Lines 3 to 9**

```python
from secretless_app.application.check_health import CheckHealth
from secretless_app.application.ports import BlobStore, SecretStore
from secretless_app.application.save_upload import SaveUpload
from secretless_app.application.services import Services
from secretless_app.infrastructure.azure_adapters import BlobUploads, KeyVaultSecretStore, build_credential
from secretless_app.infrastructure.memory_adapters import DEMO_SECRET_VALUE, InMemoryBlobStore, InMemorySecretStore
from secretless_app.infrastructure.settings import ConfigError, Settings
```

What happens, step by step:

- `CheckHealth` from the repository's own module `secretless_app.application.check_health`: Read the partner key and report its length (defined in `src/secretless_app/application/check_health.py`)
- `BlobStore` from the repository's own module `secretless_app.application.ports`: Writes blobs into the uploads container (defined in `src/secretless_app/application/ports.py`)
- `SecretStore` from the repository's own module `secretless_app.application.ports`: Reads named secrets (defined in `src/secretless_app/application/ports.py`)
- `SaveUpload` from the repository's own module `secretless_app.application.save_upload`: Validate the name and the size, then write the blob (overwriting a blob of the same name) (defined in `src/secretless_app/application/save_upload.py`)
- `Services` from the repository's own module `secretless_app.application.services`: Every use case of the app (defined in `src/secretless_app/application/services.py`)
- `BlobUploads` from the repository's own module `secretless_app.infrastructure.azure_adapters`: Writes blobs with the Storage Blob Data Contributor role on one container (defined in `src/secretless_app/infrastructure/azure_adapters.py`)
- `KeyVaultSecretStore` from the repository's own module `secretless_app.infrastructure.azure_adapters`: Reads secrets with the Key Vault Secrets User role (defined in `src/secretless_app/infrastructure/azure_adapters.py`)
- `build_credential` from the repository's own module `secretless_app.infrastructure.azure_adapters`: In Azure the managed identity named by `client_id` answers; on a laptop `az login` does (defined in `src/secretless_app/infrastructure/azure_adapters.py`)
- `DEMO_SECRET_VALUE` from the repository's own module `secretless_app.infrastructure.memory_adapters`.
- `InMemoryBlobStore` from the repository's own module `secretless_app.infrastructure.memory_adapters`: A dictionary of blobs that can pretend the Blob Data Contributor role was removed (defined in `src/secretless_app/infrastructure/memory_adapters.py`)
- `InMemorySecretStore` from the repository's own module `secretless_app.infrastructure.memory_adapters`: A dictionary of secrets that can pretend the Secrets User role was removed (defined in `src/secretless_app/infrastructure/memory_adapters.py`)
- `ConfigError` from the repository's own module `secretless_app.infrastructure.settings`: One or more settings are missing or malformed; the message lists all of them (defined in `src/secretless_app/infrastructure/settings.py`)
- `Settings` from the repository's own module `secretless_app.infrastructure.settings`: Everything the app reads from the environment (defined in `src/secretless_app/infrastructure/settings.py`)

**Lines 12 to 28**

```python
def build_services(settings: Settings) -> Services:
    """Return the use cases wired to Azure (`BACKEND=azure`) or to memory (`BACKEND=memory`)."""
    secrets: SecretStore
    blobs: BlobStore
    if settings.backend == "memory":
        secrets = InMemorySecretStore({settings.secret_name: DEMO_SECRET_VALUE}, denied="vault" in settings.memory_deny)
        blobs = InMemoryBlobStore(denied="blob" in settings.memory_deny)
    else:
        if settings.vault_url is None or settings.storage_url is None:
            raise ConfigError("VAULT_URL and STORAGE_URL are required when BACKEND=azure")
        credential = build_credential(settings.client_id)
        secrets = KeyVaultSecretStore(settings.vault_url, credential)
        blobs = BlobUploads(settings.storage_url, settings.container, credential)
    return Services(
        check_health=CheckHealth(secrets, settings.secret_name),
        save_upload=SaveUpload(blobs, settings.max_upload_bytes),
    )
```

The docstring in the code says: Return the use cases wired to Azure (`BACKEND=azure`) or to memory (`BACKEND=memory`).

**Function `build_services`** takes `settings` (type `Settings`); gives back `Services`.

What happens, step by step:

- Sets `secrets` with type `SecretStore`.
- Sets `blobs` with type `BlobStore`.
- If `settings.backend` equals `'memory'`:
  - Sets `secrets` to the result of calling `InMemorySecretStore` with `{settings.secret_name: DEMO_SECRET_VALUE}`; `denied` set to `'vault' in settings.memory_deny`.
  - Sets `blobs` to the result of calling `InMemoryBlobStore(denied='blob' in settings.memory_deny)`.
- Otherwise:
  - If `settings.vault_url` is exactly `None` **or** `settings.storage_url` is exactly `None`:
    - Raises `ConfigError('VAULT_URL and STORAGE_URL are required when BACKEND=azure')`.
  - Sets `credential` to the result of calling `build_credential(settings.client_id)`.
  - Sets `secrets` to the result of calling `KeyVaultSecretStore(settings.vault_url, credential)`.
  - Sets `blobs` to the result of calling `BlobUploads(settings.storage_url, settings.container, credential)`.
- Returns `Services(check_health=CheckHealth(secrets, settings.secret_name), save_upload=SaveUpload(blobs, settings.max_…` (long; see the quote).

#### `src/secretless_app/interfaces/__init__.py`

1 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""The HTTP surface; may use every other layer, nothing uses it."""
```

The module docstring says: The HTTP surface; may use every other layer, nothing uses it.


### Where else this technology appears

Lines of other files that use this technology are explained line by line in the notes of those files. This table lists where to find them.

| File | Matching lines | Explained in |
|---|---|---|
| `.github/workflows/ci.yml` | 18 to 20, 36 to 38 | [github-actions.md](github-actions.md) |
| `Dockerfile` | 3, 6, 13, 20 | [docker.md](docker.md) |
| `Makefile` | 2 to 4 | [make.md](make.md) |
| `pyproject.toml` | 10 | [pyproject-toml.md](pyproject-toml.md) |

## Try it yourself

Check which Python the project's virtual environment uses.

```bash
.venv/bin/python --version
```

You should see something like this:

```text
Python 3.13.12
```

Watch the secret refuse to print itself.

```bash
.venv/bin/python -c "from secretless_app.domain.secret import Secret; s = Secret('abc123'); print(repr(s), f'{s}', len(s))"
```

You should see something like this:

```text
Secret(<redacted>) Secret(<redacted>) 6
```

Try a good name and two bad ones.

```bash
.venv/bin/python -c "from secretless_app.domain.blob_name import BlobName
for name in ('hello.txt', '../x', 'a..b'):
    try:
        print(BlobName(name))
    except Exception as error:
        print(type(error).__name__)"
```

You should see something like this:

```text
BlobName(value='hello.txt')
InvalidBlobNameError
InvalidBlobNameError
```

A frozen dataclass refuses to change.

```bash
.venv/bin/python -c "from secretless_app.domain.blob_name import BlobName; b = BlobName('x'); b.value = 'y'"
```

You should see something like this:

```text
Traceback (most recent call last):
  File "<string>", line 1, in <module>
    from secretless_app.domain.blob_name import BlobName; b = BlobName('x'); b.value = 'y'
                                                                             ^^^^^^^
  File "<string>", line 16, in __setattr__
dataclasses.FrozenInstanceError: cannot assign to field 'value'
```

## Mistakes people make

- Running `python` from the system instead of the project's `.venv/bin/python`. The packages are installed in the virtual environment only. The Makefile always calls `.venv/bin/...`.
- Treating type hints as checks. They are notes for people and for mypy; Python itself will happily run a wrong type.
- Catching `Exception` and hiding the error. This repository catches the narrow errors it expects and lets everything else stop the program, so a bug is visible.
- Mutable default arguments and shared global state. This repository uses frozen dataclasses (objects that cannot change after creation) and passes dependencies in.
- Using `==` to compare with `None`. Use `is None`.

## Check yourself

1. **What does `python -m package.module` do?**
   Answer: It runs a module by its package name instead of by file path, so imports inside the package work.

2. **What is a virtual environment for?**
   Answer: It keeps the packages of one project in one folder (`.venv/`), separate from other projects and from the system Python.

3. **Does Python check type hints when the program runs?**
   Answer: No. Only a tool such as mypy checks them, before the program runs.

4. **What is a frozen dataclass?**
   Answer: A class whose objects cannot be changed after they are created; Python writes `__init__` and comparison methods for it.

5. **What is the standard library?**
   Answer: The modules that come with Python itself, so no installation is needed to use them.

## Further reading

- The Python tutorial: https://docs.python.org/3.13/tutorial/ (Python 3.13 is used here; the project needs 3.12 or newer).
- `dataclasses`: https://docs.python.org/3.13/library/dataclasses.html
- `typing` (`Protocol`, `Literal`): https://docs.python.org/3.13/library/typing.html
- `venv`: https://docs.python.org/3.13/library/venv.html
