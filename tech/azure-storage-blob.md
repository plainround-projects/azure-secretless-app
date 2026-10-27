# azure-storage-blob

*The client the app uses to write uploaded files to a container. Pinned here: azure-storage-blob 12.31.0.*

## What it is

`azure-storage-blob` is the Python client for **Azure Blob Storage**. A **blob** is a file stored in the cloud inside a **container** (a folder-like grouping) of a **storage account**. `ContainerClient(...).upload_blob(name, data)` writes one.

## Why this repository uses it

`/upload/<name>` writes the request body to the `uploads` container, which proves that the blob role works. The role is scoped to that one container.

## Where it appears

| File | What it does with it |
|---|---|
| `src/secretless_app/infrastructure/azure_adapters.py` | `BlobUploads` wraps `ContainerClient`. |
| `src/secretless_app/application/save_upload.py` | The use case that validates the name and size before calling the port. |
| `tests/unit/infrastructure/test_azure_adapters.py` | Tests the adapter against a stub. |

## How it works underneath

Uploads are HTTPS `PUT` requests to `https://<account>.blob.core.windows.net/<container>/<blob>` with a bearer token. The service checks the identity's roles at the container, account or resource group scope. With `overwrite=True` a blob of the same name is replaced.

Errors come back as `HttpResponseError`; the storage-specific code, such as `AuthorizationPermissionMismatch` (the identity is known but its roles do not allow the operation), is available as `error_code`. The client times out connections (`connection_timeout`, `read_timeout`) and retries transient failures.

## Walkthrough of this repository's use

### The adapter

```python
class BlobUploads:
    """Writes blobs with the Storage Blob Data Contributor role on one container."""

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

    def put(self, name: BlobName, data: bytes) -> None:
        """Create or overwrite the blob."""
        try:
            self._container.upload_blob(name.value, data, overwrite=True)
        except Exception as error:
            raise translate("blob", error) from error
```

`ContainerClient` is bound to one account URL and one container, so the object can only touch that container. `connection_timeout` and `read_timeout` bound how long a request may wait. `upload_blob(name, data, overwrite=True)` writes the bytes; the name is `name.value`, the validated text of a `BlobName`. Errors become named app errors in the same way as in the Key Vault adapter.

### Checks before the call

```python
    def run(self, raw_name: str, data: bytes) -> BlobName:
        """Return the saved name; raise `InvalidBlobNameError`, `UploadTooLargeError` or `DependencyError`."""
        name = BlobName(raw_name)
        if len(data) > self.max_bytes:
            raise UploadTooLargeError(len(data), self.max_bytes)
        self.blobs.put(name, data)
        return name
```

The use case builds a `BlobName` first (an invalid name raises before any call), checks the size, and only then calls `blobs.put`. The size check is in the application layer, not only in Flask, so the rule holds whatever the web layer does.

### Limits of the key

The storage account has shared key access switched off, so a connection string or account key would fail with `KeyBasedAuthenticationNotPermitted`. The code never has one. See `azure-storage.md`.

## Try it yourself

Confirm the pinned version.

```bash
.venv/bin/pip show azure-storage-blob | sed -n 1,2p
```

You should see something like this:

```text
Name: azure-storage-blob
Version: 12.31.0
```

Run the use-case tests (names, sizes, denial).

```bash
.venv/bin/python -m pytest tests/unit/application -q -p no:cacheprovider
```

You should see something like this:

```text
........                                                                 [100%]
8 passed in 0.03s
```

## Mistakes people make

- Using a connection string or an account key. Shared key access is switched off on the account, so those would fail.
- Letting the caller choose any blob name; here names are validated first, so a name cannot contain a slash or `..`.
- Forgetting `overwrite=True` and getting `BlobAlreadyExists` on a second upload.
- Reading a whole large upload into memory. This app caps the size.
- Granting the role on the whole account when one container is enough.

## Check yourself

1. **What is a blob?**
   Answer: A file stored in a container of a storage account.

2. **How does the client authenticate here?**
   Answer: With a bearer token from the managed identity; no key.

3. **What does `AuthorizationPermissionMismatch` mean?**
   Answer: The caller is known but has no role that allows this operation.

4. **What does `overwrite=True` do?**
   Answer: Replaces an existing blob of the same name.

5. **Why validate blob names?**
   Answer: To stop names with slashes or `..` and keep every blob in the one container.

## Further reading

- azure-storage-blob 12.31: https://learn.microsoft.com/en-us/python/api/overview/azure/storage-blob-readme
