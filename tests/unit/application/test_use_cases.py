import pytest

from secretless_app.application.check_health import CheckHealth
from secretless_app.application.save_upload import SaveUpload
from secretless_app.domain.errors import AccessDeniedError, DependencyError, InvalidBlobNameError, UploadTooLargeError
from secretless_app.infrastructure.memory_adapters import InMemoryBlobStore, InMemorySecretStore
from tests.conftest import SECRET_NAME, SECRET_VALUE


def test_health_reports_the_length_of_the_key_and_not_the_key():
    report = CheckHealth(InMemorySecretStore({SECRET_NAME: SECRET_VALUE}), SECRET_NAME).run()
    assert report.key_length == len(SECRET_VALUE)
    assert SECRET_VALUE not in repr(report)


def test_health_surfaces_a_missing_vault_role_as_access_denied():
    check = CheckHealth(InMemorySecretStore({SECRET_NAME: SECRET_VALUE}, denied=True), SECRET_NAME)
    with pytest.raises(AccessDeniedError) as caught:
        check.run()
    assert caught.value.code == "ForbiddenByRbac"


def test_health_surfaces_a_missing_secret_as_a_dependency_failure_that_is_not_a_denial():
    with pytest.raises(DependencyError) as caught:
        CheckHealth(InMemorySecretStore({}), SECRET_NAME).run()
    assert caught.value.code == "SecretNotFound"
    assert not isinstance(caught.value, AccessDeniedError)


def test_an_upload_lands_in_the_container_under_its_name():
    blobs = InMemoryBlobStore()
    saved = SaveUpload(blobs, max_bytes=10).run("hello.txt", b"hi there")
    assert saved.value == "hello.txt"
    assert blobs.blobs == {"hello.txt": b"hi there"}


def test_an_upload_overwrites_a_blob_of_the_same_name():
    blobs = InMemoryBlobStore()
    use_case = SaveUpload(blobs, max_bytes=10)
    use_case.run("a.txt", b"one")
    use_case.run("a.txt", b"two")
    assert blobs.blobs == {"a.txt": b"two"}


def test_an_upload_at_the_limit_is_accepted_and_one_byte_over_is_refused():
    use_case = SaveUpload(InMemoryBlobStore(), max_bytes=4)
    use_case.run("ok.bin", b"1234")
    with pytest.raises(UploadTooLargeError):
        use_case.run("big.bin", b"12345")


def test_a_bad_name_is_refused_before_anything_is_written():
    blobs = InMemoryBlobStore()
    with pytest.raises(InvalidBlobNameError):
        SaveUpload(blobs, max_bytes=10).run("../x", b"data")
    assert blobs.blobs == {}


def test_an_upload_surfaces_a_missing_blob_role_as_access_denied():
    with pytest.raises(AccessDeniedError) as caught:
        SaveUpload(InMemoryBlobStore(denied=True), max_bytes=10).run("a.txt", b"data")
    assert caught.value.code == "AuthorizationPermissionMismatch"
