import pytest

from secretless_app.domain.blob_name import BlobName
from secretless_app.domain.errors import InvalidBlobNameError
from secretless_app.domain.secret import Secret


@pytest.mark.parametrize("value", ["hello.txt", "a", "Report_2026-10.csv", "x" * 128, "v1.2.3.tar.gz"])
def test_a_plain_file_name_is_accepted(value):
    assert BlobName(value).value == value


@pytest.mark.parametrize(
    "value",
    ["", ".hidden", "-dash", "has space", "a/b", "..", "a..b", "x" * 129, "naïve.txt", "a\nb", "a\\b"],
)
def test_a_name_that_could_escape_or_confuse_the_path_is_refused(value):
    with pytest.raises(InvalidBlobNameError):
        BlobName(value)


def test_a_secret_never_shows_its_value_when_printed_or_formatted():
    secret = Secret("hunter2-value")
    for rendering in (repr(secret), str(secret), f"{secret}", f"{secret!r}", "%s" % secret):  # noqa: UP031
        assert "hunter2" not in rendering


def test_a_secret_reveals_its_value_and_its_length_on_request():
    secret = Secret("hunter2-value")
    assert secret.reveal() == "hunter2-value"
    assert len(secret) == 13
