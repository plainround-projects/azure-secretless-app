"""The composition root: build the use cases around the adapters the settings select."""

from secretless_app.application.check_health import CheckHealth
from secretless_app.application.ports import BlobStore, SecretStore
from secretless_app.application.save_upload import SaveUpload
from secretless_app.application.services import Services
from secretless_app.infrastructure.azure_adapters import BlobUploads, KeyVaultSecretStore, build_credential
from secretless_app.infrastructure.memory_adapters import DEMO_SECRET_VALUE, InMemoryBlobStore, InMemorySecretStore
from secretless_app.infrastructure.settings import ConfigError, Settings


def build_services(settings: Settings) -> Services:
    """Return the use cases wired to Azure (`BACKEND=azure`) or to memory (`BACKEND=memory`)."""
    secrets: SecretStore
    blobs: BlobStore
    if settings.backend == "memory":
        secrets = InMemorySecretStore({settings.secret_name: DEMO_SECRET_VALUE}, denied="vault" in settings.memory_deny)
        blobs = InMemoryBlobStore(denied="blob" in settings.memory_deny)
    else:
        if settings.vault_url is None or settings.storage_url is None:
            raise ConfigError("VAULT_URL and STORAGE_URL are required when BACKEND=azure")
        credential = build_credential(settings.client_id)
        secrets = KeyVaultSecretStore(settings.vault_url, credential)
        blobs = BlobUploads(settings.storage_url, settings.container, credential)
    return Services(
        check_health=CheckHealth(secrets, settings.secret_name),
        save_upload=SaveUpload(blobs, settings.max_upload_bytes),
    )
