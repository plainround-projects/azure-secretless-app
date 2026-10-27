"""The upload use case: proves the blob role works by writing a file."""

from dataclasses import dataclass

from secretless_app.application.ports import BlobStore
from secretless_app.domain.blob_name import BlobName
from secretless_app.domain.errors import UploadTooLargeError


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
