import json
import logging

import pytest

from secretless_app.application.check_health import CheckHealth
from secretless_app.application.save_upload import SaveUpload
from secretless_app.application.services import Services
from secretless_app.infrastructure.memory_adapters import InMemoryBlobStore, InMemorySecretStore
from secretless_app.interfaces.http import create_app
from tests.conftest import SECRET_NAME, SECRET_VALUE


@pytest.fixture
def client(services):
    return create_app(services, max_upload_bytes=1024).test_client()


def _denied_client(*, vault: bool = False, blob: bool = False):
    services = Services(
        CheckHealth(InMemorySecretStore({SECRET_NAME: SECRET_VALUE}, denied=vault), SECRET_NAME),
        SaveUpload(InMemoryBlobStore(denied=blob), max_bytes=1024),
    )
    return create_app(services, max_upload_bytes=1024).test_client()


def test_health_returns_the_key_length_and_never_the_key(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok", "key_length": len(SECRET_VALUE)}
    assert SECRET_VALUE not in response.get_data(as_text=True)


def test_live_answers_without_touching_a_dependency():
    client = _denied_client(vault=True, blob=True)
    assert client.get("/live").get_json() == {"status": "alive"}


def test_an_upload_returns_201_and_stores_the_body(client, blobs):
    response = client.post("/upload/hello.txt", data=b"hello")
    assert response.status_code == 201
    assert response.get_json() == {"saved": "hello.txt"}
    assert blobs.blobs == {"hello.txt": b"hello"}


def test_a_bad_name_is_a_400(client):
    response = client.post("/upload/.hidden", data=b"x")
    assert response.status_code == 400
    assert response.get_json()["error"] == "invalid_name"


def test_a_body_over_the_limit_is_a_413_before_the_app_reads_it(client, blobs):
    response = client.post("/upload/big.bin", data=b"x" * 2048)
    assert response.status_code == 413
    assert response.get_json()["error"] == "upload_too_large"
    assert blobs.blobs == {}


def test_a_missing_blob_role_is_a_502_with_the_code_and_the_detail_only_in_the_log(caplog):
    with caplog.at_level(logging.ERROR, logger="secretless_app.http"):
        response = _denied_client(blob=True).post("/upload/a.txt", data=b"x")
    assert response.status_code == 502
    assert response.get_json() == {
        "error": "upstream_access_denied",
        "service": "blob",
        "code": "AuthorizationPermissionMismatch",
    }
    record = caplog.records[-1]
    assert record.service == "blob"
    assert "not authorized" in record.detail


def test_a_missing_vault_role_is_a_502_naming_the_rbac_code():
    response = _denied_client(vault=True).get("/health")
    assert response.status_code == 502
    assert response.get_json()["code"] == "ForbiddenByRbac"


def test_a_missing_secret_is_a_502_that_is_not_a_denial():
    services = Services(
        CheckHealth(InMemorySecretStore({}), SECRET_NAME),
        SaveUpload(InMemoryBlobStore(), max_bytes=1024),
    )
    response = create_app(services, max_upload_bytes=1024).test_client().get("/health")
    assert response.status_code == 502
    assert response.get_json()["error"] == "upstream_failure"


def test_unknown_routes_and_wrong_methods_answer_in_json(client):
    assert client.get("/nope").get_json() == {"error": "not_found"}
    assert client.get("/upload/a.txt").status_code == 405


def test_every_request_is_logged_with_status_and_duration(client, caplog):
    with caplog.at_level(logging.INFO, logger="secretless_app.http"):
        client.get("/live")
    record = caplog.records[-1]
    assert (record.method, record.path, record.status) == ("GET", "/live", 200)
    assert record.duration_ms >= 0
    json.dumps(record.__dict__, default=str)  # the whole record serializes
