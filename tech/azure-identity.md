# azure-identity (and azure-core)

*The library that gets Azure access tokens with no stored secret. Pinned here: azure-identity 1.27.0, azure-core 1.41.0.*

## What it is

`azure-identity` is the Python library that gets **access tokens** for Azure. A token is a short-lived proof of who you are. The class `DefaultAzureCredential` tries several ways of getting one, in order, so the same code works on a laptop and in Azure. This library depends on `azure-core`, the shared base of all Azure Python libraries (it provides the retry policy and the error classes such as `HttpResponseError`).

## Why this repository uses it

This is the heart of the lesson. The app must reach Key Vault and Storage with a managed identity and nothing else. `DefaultAzureCredential` is the one object that does it: in Azure it asks the identity service, and on a laptop it uses the `az login` session, so the same code runs in both places.

## Where it appears

| File | What it does with it |
|---|---|
| `src/secretless_app/infrastructure/azure_adapters.py` | `build_credential` creates the credential; the two adapters pass it to the service clients. |
| `src/secretless_app/infrastructure/azure_errors.py` | Translates `azure-core` exceptions into the app's named errors. |
| `tests/unit/infrastructure/test_azure_adapters.py` | Builds the credential without contacting Azure. |

## How it works underneath

`DefaultAzureCredential` is a **chain**. It tries, in order, credentials that read environment variables, a workload identity, a **managed identity**, a shared token cache, the Azure CLI sign-in, and a few more. The first one that can produce a token wins; if one fails, it tries the next.

Inside Azure the managed identity answers: the library asks a local address, the **instance metadata service**, for a token, and Azure issues one for the identity attached to the resource. On a laptop there is no such service, so the chain falls through to the `az login` session. If an app has several identities attached, `managed_identity_client_id` says which one to use.

A credential object is passed to a service client (`SecretClient`, `BlobServiceClient`). The client asks it for a token for the right audience each time it needs one; tokens are cached and refreshed. No password or key is stored anywhere.

## Walkthrough of this repository's use

### Creating the credential

```python
def build_credential(client_id: str | None) -> DefaultAzureCredential:
    """In Azure the managed identity named by `client_id` answers; on a laptop `az login` does."""
    return DefaultAzureCredential(managed_identity_client_id=client_id)
```

`managed_identity_client_id` names which user-assigned identity to use. In Azure, `AZURE_CLIENT_ID` carries that id (an address of the identity, not a secret). On a laptop the variable is empty (`None`), the managed identity step finds nothing, and the chain moves on to the Azure CLI sign-in. Creating the object makes no network call; tokens are requested only when a service client first needs one.

### Passing it to a client

```python
class KeyVaultSecretStore:
    """Reads secrets with the Key Vault Secrets User role."""

    def __init__(self, vault_url: str, credential: DefaultAzureCredential) -> None:
        """Connect lazily; the SDK retries transient failures with exponential backoff."""
        self._client = SecretClient(vault_url=vault_url, credential=credential, retry_total=_RETRY_TOTAL)
```

The same credential object is given to the Key Vault client and to the Blob client (see `azure-keyvault-secrets.md` and `azure-storage-blob.md`). Each client asks it for a token for its own service.

### Errors from `azure-core`

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
```

`HttpResponseError` is the base class of "the service answered with an error"; it has a `status_code`. `ClientAuthenticationError` means no token could be obtained. `ServiceRequestError` and `ServiceResponseError` are network failures. The function turns each into one of the app's own errors, and only a 403 becomes `AccessDeniedError`.

### Picking the most specific code

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

Key Vault puts `ForbiddenByRbac` in an inner error; Storage exposes `error_code` (for example `AuthorizationPermissionMismatch`). The helper prefers the inner code, then the storage code, then the generic one, because the specific code says exactly what is missing.

### Where else this technology appears

Lines of other files that use this technology are explained line by line in the notes of those files. This table lists where to find them.

| File | Matching lines | Explained in |
|---|---|---|
| `src/secretless_app/infrastructure/azure_adapters.py` | 1 to 3, 16 to 18, 24, 40 | [azure-keyvault-secrets.md](azure-keyvault-secrets.md) |
| `tests/unit/infrastructure/test_azure_adapters.py` | 8, 15, 74 to 75 | [pytest.md](pytest.md) |
| `infra/modules/container_app/main.tf` | 16 | [azure-container-apps.md](azure-container-apps.md) |
| `pyproject.toml` | 16 | [pyproject-toml.md](pyproject-toml.md) |
| `tests/unit/infrastructure/test_azure_errors.py` | 10 | [pytest.md](pytest.md) |

## Try it yourself

Create a credential; no network call happens.

```bash
.venv/bin/python -c "from azure.identity import DefaultAzureCredential; c = DefaultAzureCredential(managed_identity_client_id=None); print(type(c).__name__)"
```

You should see something like this:

```text
DefaultAzureCredential
```

Run the tests that feed the translator constructed SDK errors.

```bash
.venv/bin/python -m pytest tests/unit/infrastructure/test_azure_errors.py -q -p no:cacheprovider
```

You should see something like this:

```text
.......                                                                  [100%]
7 passed in 1.11s
```

Confirm the pinned versions.

```bash
.venv/bin/pip show azure-identity azure-core | grep -E '^(Name|Version)'
```

You should see something like this:

```text
Name: azure-identity
Version: 1.27.0
Name: azure-core
Version: 1.41.0
```

## Mistakes people make

- Setting `AZURE_CLIENT_SECRET` in production environments, which turns the chain's first step into a stored secret.
- Not naming the identity when several are attached.
- Creating a new credential for every request. One shared object caches tokens.
- Assuming a signed-in developer has the roles the app's identity has. They are different principals.
- Catching every exception from a client call and hiding authentication errors.

## Check yourself

1. **What does `DefaultAzureCredential` do?**
   Answer: Tries several credential sources in order and uses the first that works.

2. **What answers inside Azure?**
   Answer: The managed identity, through the instance metadata service.

3. **What answers on a laptop?**
   Answer: Usually the `az login` session, through the Azure CLI credential.

4. **When is `managed_identity_client_id` needed?**
   Answer: When more than one identity is attached to the resource.

5. **What does `azure-core` provide?**
   Answer: The shared HTTP pipeline (retries) and error classes for all Azure libraries.

## Further reading

- azure-identity 1.27: https://learn.microsoft.com/en-us/python/api/overview/azure/identity-readme
- Credential chains: https://learn.microsoft.com/en-us/azure/developer/python/sdk/authentication/credential-chains
- azure-core 1.41: https://learn.microsoft.com/en-us/python/api/azure-core/azure.core
