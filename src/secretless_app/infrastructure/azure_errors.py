"""Turn Azure SDK exceptions into the application's named errors."""

from azure.core.exceptions import (
    ClientAuthenticationError,
    HttpResponseError,
    ServiceRequestError,
    ServiceResponseError,
)

from secretless_app.domain.errors import AccessDeniedError, DependencyError, SecretlessError

_DETAIL_LIMIT = 2000


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
        return DependencyError(service, "Unreachable", detail)
    raise error


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
