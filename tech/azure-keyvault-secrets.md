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
