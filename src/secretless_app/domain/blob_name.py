"""The naming rule for uploaded blobs."""

import re
from dataclasses import dataclass

from secretless_app.domain.errors import InvalidBlobNameError

_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}")


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
