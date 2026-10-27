"""Named errors. The interfaces layer maps each one to an HTTP status."""


class SecretlessError(Exception):
    """Base class for every error this application raises on purpose."""


class InvalidBlobNameError(SecretlessError):
    """The requested blob name breaks the naming rule."""


class UploadTooLargeError(SecretlessError):
    """The upload is bigger than the configured limit."""

    def __init__(self, size: int, limit: int) -> None:
        super().__init__(f"upload of {size} bytes exceeds the limit of {limit} bytes")
        self.size = size
        self.limit = limit


class DependencyError(SecretlessError):
    """An Azure service could not be used; `code` is the service's own error code."""

    def __init__(self, service: str, code: str, detail: str) -> None:
        super().__init__(f"{service}: {code}: {detail}")
        self.service = service
        self.code = code
        self.detail = detail


class AccessDeniedError(DependencyError):
    """The app's identity is known to the service but holds no role that allows the call."""
