"""In-memory stand-ins for Key Vault and Blob Storage.

They serve the unit tests and `BACKEND=memory`, which lets a reader run the app and rehearse the denial of
step 5 (`MEMORY_DENY=blob`) without a subscription.
"""

from secretless_app.domain.blob_name import BlobName
from secretless_app.domain.errors import AccessDeniedError, DependencyError
from secretless_app.domain.secret import Secret

DEMO_SECRET_VALUE = "demo-value-123"


class InMemorySecretStore:
    """A dictionary of secrets that can pretend the Secrets User role was removed."""

    def __init__(self, secrets: dict[str, str], denied: bool = False) -> None:
        """Hold `secrets`; with `denied` every read raises `AccessDeniedError` as the vault does."""
        self._secrets = dict(secrets)
        self._denied = denied

    def get(self, name: str) -> Secret:
        """Return the secret `name`."""
        if self._denied:
            raise AccessDeniedError(
                "keyvault", "ForbiddenByRbac", "Caller is not authorized to perform action on resource."
            )
        if name not in self._secrets:
            raise DependencyError("keyvault", "SecretNotFound", f"secret {name!r} does not exist")
        return Secret(self._secrets[name])


class InMemoryBlobStore:
    """A dictionary of blobs that can pretend the Blob Data Contributor role was removed."""

    def __init__(self, denied: bool = False) -> None:
        """Start empty; with `denied` every write raises `AccessDeniedError` as Storage does."""
        self.blobs: dict[str, bytes] = {}
        self._denied = denied

    def put(self, name: BlobName, data: bytes) -> None:
        """Create or overwrite the blob."""
        if self._denied:
            raise AccessDeniedError(
                "blob",
                "AuthorizationPermissionMismatch",
                "This request is not authorized to perform this operation using this permission.",
            )
        self.blobs[name.value] = data
