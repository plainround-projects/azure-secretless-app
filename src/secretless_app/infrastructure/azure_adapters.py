"""The Key Vault and Blob Storage adapters. Both authenticate with `DefaultAzureCredential` and nothing else."""

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.storage.blob import ContainerClient

from secretless_app.domain.blob_name import BlobName
from secretless_app.domain.secret import Secret
from secretless_app.infrastructure.azure_errors import translate

_CONNECTION_TIMEOUT_SECONDS = 5
_READ_TIMEOUT_SECONDS = 30
_RETRY_TOTAL = 3


def build_credential(client_id: str | None) -> DefaultAzureCredential:
    """In Azure the managed identity named by `client_id` answers; on a laptop `az login` does."""
    return DefaultAzureCredential(managed_identity_client_id=client_id)


class KeyVaultSecretStore:
    """Reads secrets with the Key Vault Secrets User role."""

    def __init__(self, vault_url: str, credential: DefaultAzureCredential) -> None:
        """Connect lazily; the SDK retries transient failures with exponential backoff."""
        self._client = SecretClient(vault_url=vault_url, credential=credential, retry_total=_RETRY_TOTAL)

    def get(self, name: str) -> Secret:
        """Return the secret `name`."""
        try:
            value = self._client.get_secret(name).value
        except Exception as error:
            raise translate("keyvault", error) from error
        return Secret(value or "")


class BlobUploads:
    """Writes blobs with the Storage Blob Data Contributor role on one container."""

    def __init__(self, storage_url: str, container: str, credential: DefaultAzureCredential) -> None:
        """Bind to one container; the account URL is an address, not a secret."""
        self._container = ContainerClient(
            account_url=storage_url,
            container_name=container,
            credential=credential,
            retry_total=_RETRY_TOTAL,
            connection_timeout=_CONNECTION_TIMEOUT_SECONDS,
            read_timeout=_READ_TIMEOUT_SECONDS,
        )

    def put(self, name: BlobName, data: bytes) -> None:
        """Create or overwrite the blob."""
        try:
            self._container.upload_blob(name.value, data, overwrite=True)
        except Exception as error:
            raise translate("blob", error) from error
