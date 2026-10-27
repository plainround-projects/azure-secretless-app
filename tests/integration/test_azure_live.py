"""The real adapters against the deployed resources. Skipped unless RUN_AZURE_TESTS=1 and you are signed in.

Run it after `make deploy`, with the three addresses exported (see docs/RUNBOOK.md): `make test-azure`.
"""

import os
import uuid

import pytest

from secretless_app.domain.blob_name import BlobName
from secretless_app.infrastructure.azure_adapters import BlobUploads, KeyVaultSecretStore, build_credential
from secretless_app.infrastructure.settings import Settings

pytestmark = [
    pytest.mark.azure,
    pytest.mark.skipif(os.environ.get("RUN_AZURE_TESTS") != "1", reason="set RUN_AZURE_TESTS=1 after deploying"),
]


@pytest.fixture(scope="module")
def settings() -> Settings:
    return Settings.from_env(os.environ)


def test_the_signed_in_identity_can_read_the_partner_key(settings):
    credential = build_credential(settings.client_id)
    secret = KeyVaultSecretStore(settings.vault_url or "", credential).get(settings.secret_name)
    assert len(secret) > 0


def test_the_signed_in_identity_can_write_a_blob(settings):
    credential = build_credential(settings.client_id)
    BlobUploads(settings.storage_url or "", settings.container, credential).put(
        BlobName(f"live-test-{uuid.uuid4().hex[:8]}.txt"), b"written by the live test"
    )
