from typing import Any, cast

import pytest
from azure.core.exceptions import (
    ClientAuthenticationError,
    HttpResponseError,
    ResourceNotFoundError,
    ServiceRequestError,
)
from azure.identity import CredentialUnavailableError

from secretless_app.domain.errors import AccessDeniedError, DependencyError
from secretless_app.infrastructure.azure_errors import translate


class _Response:  # the three attributes the SDK reads from a response
    def __init__(self, status_code: int, reason: str = "") -> None:
        self.status_code = status_code
        self.reason = reason
        self.headers: dict[str, str] = {}
        self.content_type = "application/json"

    def text(self) -> str:
        return ""


def _response(status_code: int, reason: str) -> Any:
    return cast(Any, _Response(status_code, reason))


def _vault_forbidden() -> HttpResponseError:
    error = HttpResponseError(
        message="(Forbidden) Caller is not authorized to perform action on resource.\n"
        "Caller: appid=1111;oid=2222;iss=https://sts.windows.net/3333/\n"
        "Action: 'Microsoft.KeyVault/vaults/secrets/getSecret/action'",
        response=_response(403, "Forbidden"),
    )
    error.error = type("Odata", (), {"code": "Forbidden", "innererror": {"code": "ForbiddenByRbac"}})()
    return error


def _blob_forbidden() -> HttpResponseError:
    error = HttpResponseError(
        message="This request is not authorized to perform this operation using this permission.",
        response=_response(403, "This request is not authorized to perform this operation using this permission."),
    )
    error.error_code = "AuthorizationPermissionMismatch"  # type: ignore[attr-defined]
    return error


def test_a_vault_403_becomes_access_denied_with_the_rbac_code_and_the_caller_in_the_detail():
    result = translate("keyvault", _vault_forbidden())
    assert isinstance(result, AccessDeniedError)
    assert result.code == "ForbiddenByRbac"
    assert "oid=2222" in result.detail
    assert "getSecret" in result.detail


def test_a_blob_403_becomes_access_denied_with_the_storage_error_code():
    result = translate("blob", _blob_forbidden())
    assert isinstance(result, AccessDeniedError)
    assert result.code == "AuthorizationPermissionMismatch"


def test_a_404_is_a_dependency_failure_and_not_a_denial():
    result = translate("keyvault", ResourceNotFoundError(message="gone", response=_response(404, "Not Found")))
    assert type(result) is DependencyError
    assert result.code == "Not Found"


def test_a_credential_that_cannot_get_a_token_is_an_authentication_failure():
    for error in (ClientAuthenticationError("no token"), CredentialUnavailableError("no source")):
        result = translate("blob", error)
        assert type(result) is DependencyError
        assert result.code == "AuthenticationFailed"


def test_a_network_error_is_unreachable():
    result = translate("blob", ServiceRequestError("connection refused"))
    assert result.code == "Unreachable"  # type: ignore[attr-defined]


def test_an_unexpected_exception_is_not_swallowed():
    with pytest.raises(ZeroDivisionError):
        translate("blob", ZeroDivisionError())


def test_a_very_long_message_is_cut_so_one_log_line_stays_bounded():
    error = ServiceRequestError("x" * 10_000)
    assert len(translate("blob", error).detail) == 2000  # type: ignore[attr-defined]
