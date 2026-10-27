"""What the use cases need from the outside world."""

from typing import Protocol

from secretless_app.domain.blob_name import BlobName
from secretless_app.domain.secret import Secret


class SecretStore(Protocol):
    """Reads named secrets."""

    def get(self, name: str) -> Secret:
        """Return the current value of the secret `name`."""
        ...


class BlobStore(Protocol):
    """Writes blobs into the uploads container."""

    def put(self, name: BlobName, data: bytes) -> None:
        """Create or overwrite the blob `name` with `data`."""
        ...
