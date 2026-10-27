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
