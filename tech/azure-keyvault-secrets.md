# azure-keyvault-secrets

*The client the app uses to read the partner key from Key Vault. Pinned here: azure-keyvault-secrets 4.11.3.*

## What it is

`azure-keyvault-secrets` is the Python client for the **secrets** part of Azure Key Vault. `SecretClient(vault_url, credential)` gives you methods such as `get_secret(name)`. It sends HTTPS requests to the vault with a bearer token.

## Why this repository uses it

The app's `/health` route proves that the vault role works by reading the secret `partner-api-key`. The adapter wraps the SDK so the rest of the code never imports it.

## Where it appears

| File | What it does with it |
|---|---|
| `src/secretless_app/infrastructure/azure_adapters.py` | `KeyVaultSecretStore` wraps `SecretClient`. |
| `tests/unit/infrastructure/test_azure_adapters.py` | Tests the adapter against a stub of the client. |
| `tests/integration/test_azure_live.py` | A live test, skipped unless asked, that reads the real secret. |

## How it works underneath

Each call is an HTTPS request to `https://<vault>.vault.azure.net/secrets/<name>?api-version=...` with an `Authorization: Bearer <token>` header. The vault checks the token's identity against its role assignments. If the identity has a role that allows reading secrets, the vault returns JSON with the value; otherwise it returns 403 with an error body naming the caller and the denied action.

The client has built-in **retry** with exponential backoff for transient failures (`retry_total=3` in this code). Errors arrive as `azure.core.exceptions.HttpResponseError` objects with a `status_code` and an error code.

## Walkthrough of this repository's use

### The adapter

```python
class KeyVaultSecretStore:
    """Reads secrets with the Key Vault Secrets User role."""

    def __init__(self, vault_url: str, credential: DefaultAzureCredential) -> None:
        """Connect lazily; the SDK retries transient failures with exponential backoff."""
        self._client = SecretClient(vault_url=vault_url, credential=credential, retry_total=_RETRY_TOTAL)

    def get(self, name: str) -> Secret:
        """Return the secret `name`."""
        try:
            value = self._client.get_secret(name).value
        except Exception as error:
            raise translate("keyvault", error) from error
        return Secret(value or "")
```

`SecretClient(vault_url=..., credential=..., retry_total=_RETRY_TOTAL)` builds the client. The vault URL is an address like `https://kv-secretless-12345.vault.azure.net/`. `retry_total=3` lets the SDK retry transient failures (timeouts, 5xx) with growing pauses. `get_secret(name).value` makes one HTTPS GET and returns the text. `except Exception as error: raise translate("keyvault", error) from error` converts any SDK error into a named app error and keeps the original as the cause (`from error`). The return wraps the text in `Secret`, so it cannot be printed by accident.

### The health use case

```python
class CheckHealth:
    """Read the partner key and report its length."""

    secrets: SecretStore
    secret_name: str

    def run(self) -> HealthReport:
        """Return the report, or raise `DependencyError` (`AccessDeniedError` when the role is missing)."""
        return HealthReport(key_length=len(self.secrets.get(self.secret_name)))
```

The use case asks the port for the secret and reports only `len(...)`. It never sees the SDK.

### How a stub tests it

```python
class _SecretClient:
    def __init__(self, value: str | None = "abcd", error: Exception | None = None) -> None:
        self.value, self.error = value, error
        self.asked: list[str] = []

    def get_secret(self, name: str) -> Any:
        self.asked.append(name)
        if self.error:
            raise self.error
        return SimpleNamespace(value=self.value)
```

The test replaces the adapter's `_client` with a small class that has a `get_secret` method. That checks the adapter's own logic (which name it asks for, how it converts errors) without a vault.

### Every line, in order

This part walks through every file this note is responsible for, from the first non-blank line to the last, in blocks. Each block shows the lines (the numbers say where they sit in the file) and then explains them. New ideas are explained at the first place they are needed; later blocks use them without repeating the explanation.

#### `src/secretless_app/infrastructure/azure_adapters.py`

43 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```python
"""The Key Vault and Blob Storage adapters. Both authenticate with `DefaultAzureCredential` and nothing else."""
```

**New idea.** **Azure Key Vault** stores secrets, keys and certificates behind Azure's access control and writes an audit record of every use. A program reads a secret by calling the vault with its identity, so the secret never has to sit in a file or in the program's settings.

**New idea.** **Azure Blob Storage** stores files (*blobs*) in a *storage account*. Blobs live in *containers*, which work like top-level folders, and each blob is addressed by account, container and name. (This "container" is not a Docker container.)

**New idea.** A **module** is one `.py` file. Python runs a file from the top to the bottom, once, the first time something imports it; `def` and `class` statements at the top level just create functions and classes, they do not run their bodies.

**New idea.** A **docstring** is a text in triple quotes as the very first statement of a module, class or function. It does nothing when the program runs; tools and people read it as the official description.

The module docstring says: The Key Vault and Blob Storage adapters. Both authenticate with `DefaultAzureCredential` and nothing else.

**Lines 3 to 5**

```python
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.storage.blob import ContainerClient
```

**New idea.** An **SDK** (software development kit) or *client library* is a package of ready-made code that talks to a service for you. The Azure ones turn calls such as "read this secret" into the correct web requests, add the access token and retry transient failures.

What happens, step by step:

- `DefaultAzureCredential` from `azure.identity`: tries several ways to prove identity to Azure and uses the first that works.
- `SecretClient` from `azure.keyvault.secrets`: the client for reading secrets from a Key Vault.
- `ContainerClient` from `azure.storage.blob`: the client for one blob container.

**Lines 7 to 9**

```python
from secretless_app.domain.blob_name import BlobName
from secretless_app.domain.secret import Secret
from secretless_app.infrastructure.azure_errors import translate
```

**New idea.** **HTTP** is the protocol of the web. A client sends a *request* (a method such as GET or POST, a path, headers and sometimes a body) and the server sends back a *response* with a three-digit **status code**: 200 means success, 201 created, 400 the request was bad, 403 forbidden, 404 not found, 413 too large, 502 a server behind this one failed.

What happens, step by step:

- `BlobName` from the repository's own module `secretless_app.domain.blob_name`: A blob name that is safe to use as a path segment: 1 to 128 characters, no slash, no dot-dot (defined in `src/secretless_app/domain/blob_name.py`)
- `Secret` from the repository's own module `secretless_app.domain.secret`: Holds a secret string; `repr`, `str` and formatting show a placeholder, `reveal` returns the value (defined in `src/secretless_app/domain/secret.py`)
- `translate` from the repository's own module `secretless_app.infrastructure.azure_errors`: Return `AccessDeniedError` for HTTP 403, `DependencyError` for everything else (defined in `src/secretless_app/infrastructure/azure_errors.py`)

**Lines 11 to 13**

```python
_CONNECTION_TIMEOUT_SECONDS = 5
_READ_TIMEOUT_SECONDS = 30
_RETRY_TOTAL = 3
```

What happens, step by step:

- Sets `_CONNECTION_TIMEOUT_SECONDS` to `5`.
- Sets `_READ_TIMEOUT_SECONDS` to `30`.
- Sets `_RETRY_TOTAL` to `3`.

**Lines 16 to 18**

```python
def build_credential(client_id: str | None) -> DefaultAzureCredential:
    """In Azure the managed identity named by `client_id` answers; on a laptop `az login` does."""
    return DefaultAzureCredential(managed_identity_client_id=client_id)
```

**New idea.** An **environment variable** is a named text value that the operating system hands to every program it starts, such as `PORT=8080`. It is the usual way to configure a program without changing its code, and the way a deployment passes settings that differ between machines.

**New idea.** A **managed identity** is an identity that Azure creates and looks after for a workload, with no password to store or rotate. When the workload runs, it asks a local Azure endpoint for a token for that identity. A *user-assigned* identity exists on its own and can be attached to several resources; its *client id* names it when a program asks for a token and its *principal id* names it when roles are granted.

The docstring in the code says: In Azure the managed identity named by `client_id` answers; on a laptop `az login` does.

**Function `build_credential`** takes `client_id` (type `str | None`); gives back `DefaultAzureCredential`.

**New idea.** A **type hint** such as `name: str` or `-> int` says what kind of value a parameter or result is. Python does not enforce hints when the program runs; the checker `mypy` reads them before the program runs and reports mismatches.

**New idea.** `def name(parameters):` defines a **function**: a named, reusable block of code. The indented lines under it are its body, which runs only when the function is **called** as `name(values)`. `return value` hands a result back to the caller; a function without `return` gives back `None`.

**New idea.** `A | B` in a type hint means "either an A or a B". `str | None` means "text, or nothing at all".

**New idea.** `None` is Python's value for "nothing here". Functions that find nothing return it, and a parameter that defaults to `None` means "not given".

What happens, step by step:

- Returns `DefaultAzureCredential(managed_identity_client_id=client_id)`.

Names used here:

- `DefaultAzureCredential()` finds a way to prove identity to Azure: it tries environment settings, then workload/managed identity, then developer tools such as the `az` login, in that order, and uses the first that works.

**Lines 21 to 22**

```python
class KeyVaultSecretStore:
    """Reads secrets with the Key Vault Secrets User role."""
```

**New idea.** **Azure role-based access control (RBAC)** decides who may do what. A *role* is a named bundle of permissions (for example "Key Vault Secrets User" may read secrets), a *scope* is where the grant applies (one resource, a resource group, a whole subscription), and a *role assignment* connects an identity, a role and a scope. The smaller the scope, the less a leaked identity can do.

The docstring in the code says: Reads secrets with the Key Vault Secrets User role.

**Class `KeyVaultSecretStore`**.

**New idea.** `class Name:` defines a **class**: a blueprint for objects that bundle data (attributes) with functions that work on it (methods). Calling the class, `Name(...)`, builds one object, an **instance**.

**Lines 24 to 26**

```python
    def __init__(self, vault_url: str, credential: DefaultAzureCredential) -> None:
        """Connect lazily; the SDK retries transient failures with exponential backoff."""
        self._client = SecretClient(vault_url=vault_url, credential=credential, retry_total=_RETRY_TOTAL)
```

**New idea.** A **retry** repeats an operation that failed, usually after a pause. It helps with failures that go away by themselves, such as a new permission that takes a few minutes to spread; it must be limited, so a permanent failure is reported and not repeated forever.

The docstring in the code says: Connect lazily; the SDK retries transient failures with exponential backoff.

**Method `__init__`** takes `vault_url` (type `str`), `credential` (type `DefaultAzureCredential`); gives back `None`.

**New idea.** Inside a method, the first parameter, by convention `self`, is the object the method was called on. `self.value` reads or sets an attribute of that object.

**New idea.** `__init__` is the special method Python calls right after it creates an object; it sets the object's starting attributes. Names with double underscores on both sides are **dunder methods**: Python calls them for you in response to syntax (`__init__` on creation, `__repr__` when printing, `__len__` for `len(x)`, `__eq__` for `==`).

What happens, step by step:

- Sets `self._client` to the result of calling `SecretClient(vault_url=vault_url, credential=credential, retry_total=_RETRY_TOTAL)`.

Names used here:

- `SecretClient(vault_url, credential)` is the Key Vault client for reading secrets.

**Lines 28 to 34**

```python
    def get(self, name: str) -> Secret:
        """Return the secret `name`."""
        try:
            value = self._client.get_secret(name).value
        except Exception as error:
            raise translate("keyvault", error) from error
        return Secret(value or "")
```

The docstring in the code says: Return the secret `name`.

**Method `get`** takes `name` (type `str`); gives back `Secret`.

**New idea.** `try:` runs code that might fail. `except SomeError:` runs only if that kind of error is raised inside the `try`; the program continues after the `except` block instead of stopping. `finally:` runs always, error or not, and is used for clean-up.

**New idea.** `raise Error(...)` stops the current function and signals a failure. `raise NewError(...) from error` also records the original error as the cause, so the traceback shows both.

**New idea.** `and` is true when both sides are; `or` is true when either is, and it stops at the first true side. `not` flips true and false.

What happens, step by step:

- Try:
  - Sets `value` to `self._client.get_secret(name).value`.
- If `Exception` is raised (the error is called `error`):
  - Raises `translate('keyvault', error)`, recording `error` as its cause.
- Returns `Secret(value or '')`.

Names used here:

- `get_secret` is the repository's own: no description in the code (defined in `tests/unit/infrastructure/test_azure_adapters.py`)

**Lines 37 to 38**

```python
class BlobUploads:
    """Writes blobs with the Storage Blob Data Contributor role on one container."""
```

The docstring in the code says: Writes blobs with the Storage Blob Data Contributor role on one container.

**Class `BlobUploads`**.

**Lines 40 to 49**

```python
    def __init__(self, storage_url: str, container: str, credential: DefaultAzureCredential) -> None:
        """Bind to one container; the account URL is an address, not a secret."""
        self._container = ContainerClient(
            account_url=storage_url,
            container_name=container,
            credential=credential,
            retry_total=_RETRY_TOTAL,
            connection_timeout=_CONNECTION_TIMEOUT_SECONDS,
            read_timeout=_READ_TIMEOUT_SECONDS,
        )
```

**New idea.** A **URL** is the full address of something on the web, such as `https://example.com:8443/path?x=1`: the protocol, the host name, an optional port, the path and an optional query.

**New idea.** A **timeout** is the longest a program waits for something before giving up. Without one, a call to a service that never answers would make the program wait forever.

The docstring in the code says: Bind to one container; the account URL is an address, not a secret.

**Method `__init__`** takes `storage_url` (type `str`), `container` (type `str`), `credential` (type `DefaultAzureCredential`); gives back `None`.

What happens, step by step:

- Sets `self._container` to the result of calling `ContainerClient` with `account_url` set to `storage_url`; `container_name` set to `container`; `credential` set to `credential`; `retry_total` set to `_RETRY_TOTAL`; `connection_timeout` set to `_CONNECTION_TIMEOUT_SECONDS`; `read_timeout` set to `_READ_TIMEOUT_SECONDS`.

**Lines 51 to 56**

```python
    def put(self, name: BlobName, data: bytes) -> None:
        """Create or overwrite the blob."""
        try:
            self._container.upload_blob(name.value, data, overwrite=True)
        except Exception as error:
            raise translate("blob", error) from error
```

The docstring in the code says: Create or overwrite the blob.

**Method `put`** takes `name` (type `BlobName`), `data` (type `bytes`); gives back `None`.

What happens, step by step:

- Try:
  - Calls `self._container.upload_blob(name.value, data, overwrite=True)`.
- If `Exception` is raised (the error is called `error`):
  - Raises `translate('blob', error)`, recording `error` as its cause.

Names used here:

- `upload_blob` is the repository's own: no description in the code (defined in `tests/unit/infrastructure/test_azure_adapters.py`)


### Where else this technology appears

Lines of other files that use this technology are explained line by line in the notes of those files. This table lists where to find them.

| File | Matching lines | Explained in |
|---|---|---|
| `tests/unit/infrastructure/test_azure_adapters.py` | 20, 45, 52 | [pytest.md](pytest.md) |
| `pyproject.toml` | 17 | [pyproject-toml.md](pyproject-toml.md) |

## Try it yourself

Confirm the pinned version.

```bash
.venv/bin/pip show azure-keyvault-secrets | sed -n 1,2p
```

You should see something like this:

```text
Name: azure-keyvault-secrets
Version: 4.11.3
```

Run the adapter tests.

```bash
.venv/bin/python -m pytest tests/unit/infrastructure/test_azure_adapters.py -q -p no:cacheprovider
```

You should see something like this:

```text
.....                                                                    [100%]
5 passed in 1.40s
```

See the live test skipped without a subscription.

```bash
.venv/bin/python -m pytest tests/integration -q -p no:cacheprovider
```

You should see something like this:

```text
ss                                                                       [100%]
=========================== short test summary info ============================
SKIPPED [1] tests/integration/test_azure_live.py:26: set RUN_AZURE_TESTS=1 after deploying
SKIPPED [1] tests/integration/test_azure_live.py:32: set RUN_AZURE_TESTS=1 after deploying
2 skipped in 1.27s
```

## Mistakes people make

- Logging the secret's value. The code wraps it in a class that prints as a placeholder.
- Assuming a 403 is permanent. A role granted seconds ago may not have taken effect.
- Reading the secret at import time so a missing role stops the whole app from starting.
- Using the vault URL of one vault with a secret name from another.
- Putting the vault URL in a secret. It is an address, not a secret.

## Check yourself

1. **What does `get_secret` return?**
   Answer: A secret object whose `.value` holds the text.

2. **What does the vault check before answering?**
   Answer: The caller's role assignments.

3. **What kind of exception does a refused call raise?**
   Answer: An `HttpResponseError` with status 403.

4. **What does `retry_total=3` do?**
   Answer: Retries transient failures up to three times with backoff.

5. **Is the vault URL a secret?**
   Answer: No; it is an address.

## Further reading

- azure-keyvault-secrets 4.11: https://learn.microsoft.com/en-us/python/api/overview/azure/keyvault-secrets-readme
