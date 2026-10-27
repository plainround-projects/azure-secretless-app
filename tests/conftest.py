"""Shared fixtures."""

import pytest

from secretless_app.application.check_health import CheckHealth
from secretless_app.application.save_upload import SaveUpload
from secretless_app.application.services import Services
from secretless_app.infrastructure.memory_adapters import InMemoryBlobStore, InMemorySecretStore

SECRET_NAME = "partner-api-key"
SECRET_VALUE = "demo-value-123"


@pytest.fixture
def blobs() -> InMemoryBlobStore:
    return InMemoryBlobStore()


@pytest.fixture
def services(blobs: InMemoryBlobStore) -> Services:
    secrets = InMemorySecretStore({SECRET_NAME: SECRET_VALUE})
    return Services(CheckHealth(secrets, SECRET_NAME), SaveUpload(blobs, max_bytes=1024))
