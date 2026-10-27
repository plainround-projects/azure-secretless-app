"""The adapters against a stub of the SDK client: the call made, and the error translation."""

from types import SimpleNamespace
from typing import Any

import pytest
from azure.core.exceptions import ClientAuthenticationError
from azure.identity import DefaultAzureCredential

from secretless_app.domain.blob_name import BlobName
from secretless_app.domain.errors import DependencyError
from secretless_app.infrastructure.azure_adapters import BlobUploads, KeyVaultSecretStore, build_credential


class _Credential(DefaultAzureCredential):
    def __init__(self) -> None:  # skip the real credential chain
        pass


class _SecretClient:
    def __init__(self, value: str | None = "abcd", error: Exception | None = None) -> None:
        self.value, self.error = value, error
        self.asked: list[str] = []

    def get_secret(self, name: str) -> Any:
        self.asked.append(name)
        if self.error:
            raise self.error
        return SimpleNamespace(value=self.value)


class _ContainerClient:
    def __init__(self, error: Exception | None = None) -> None:
        self.error = error
        self.calls: list[tuple[str, bytes, bool]] = []

    def upload_blob(self, name: str, data: bytes, overwrite: bool) -> None:
        self.calls.append((name, data, overwrite))
        if self.error:
            raise self.error


def test_the_vault_adapter_reads_the_named_secret():
    store = KeyVaultSecretStore("https://kv.vault.azure.net", _Credential())
    store._client = client = _SecretClient("abcd")  # type: ignore[assignment]
    assert store.get("partner-api-key").reveal() == "abcd"
    assert client.asked == ["partner-api-key"]


def test_the_vault_adapter_translates_sdk_errors():
    store = KeyVaultSecretStore("https://kv.vault.azure.net", _Credential())
    store._client = _SecretClient(error=ClientAuthenticationError("no token"))  # type: ignore[assignment]
    with pytest.raises(DependencyError) as caught:
        store.get("partner-api-key")
    assert caught.value.service == "keyvault"


def test_the_blob_adapter_overwrites_by_name():
    uploads = BlobUploads("https://st.blob.core.windows.net", "uploads", _Credential())
    uploads._container = client = _ContainerClient()  # type: ignore[assignment]
    uploads.put(BlobName("a.txt"), b"data")
    assert client.calls == [("a.txt", b"data", True)]


def test_the_blob_adapter_translates_sdk_errors():
    uploads = BlobUploads("https://st.blob.core.windows.net", "uploads", _Credential())
    uploads._container = _ContainerClient(ClientAuthenticationError("no token"))  # type: ignore[assignment]
    with pytest.raises(DependencyError) as caught:
        uploads.put(BlobName("a.txt"), b"data")
    assert caught.value.service == "blob"


def test_the_credential_is_built_without_any_secret_and_without_network_access():
    assert isinstance(build_credential("00000000-0000-0000-0000-000000000000"), DefaultAzureCredential)
    assert isinstance(build_credential(None), DefaultAzureCredential)
