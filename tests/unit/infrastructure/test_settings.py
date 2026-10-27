import pytest

from secretless_app.infrastructure.settings import ConfigError, Settings

AZURE_ENV = {
    "VAULT_URL": "https://kv-secretless-12345.vault.azure.net",
    "STORAGE_URL": "https://stsecretless12345.blob.core.windows.net",
    "AZURE_CLIENT_ID": "00000000-0000-0000-0000-000000000000",
}


def test_azure_settings_read_the_three_addresses_and_apply_defaults():
    settings = Settings.from_env(AZURE_ENV)
    assert settings.backend == "azure"
    assert settings.vault_url == AZURE_ENV["VAULT_URL"]
    assert settings.container == "uploads"
    assert settings.secret_name == "partner-api-key"
    assert settings.max_upload_bytes == 5_000_000
    assert settings.log_level == "INFO"


def test_the_client_id_is_optional_because_a_laptop_signs_in_with_az_login():
    env = {key: value for key, value in AZURE_ENV.items() if key != "AZURE_CLIENT_ID"}
    assert Settings.from_env(env).client_id is None


def test_every_problem_is_reported_at_once():
    with pytest.raises(ConfigError) as caught:
        Settings.from_env({"VAULT_URL": "http://insecure", "MAX_UPLOAD_BYTES": "-3", "LOG_LEVEL": "LOUD"})
    message = str(caught.value)
    assert "VAULT_URL" in message
    assert "STORAGE_URL" in message
    assert "MAX_UPLOAD_BYTES" in message
    assert "LOG_LEVEL" in message


def test_the_memory_backend_needs_no_addresses():
    settings = Settings.from_env({"BACKEND": "memory", "MEMORY_DENY": "blob,vault"})
    assert settings.vault_url is None
    assert settings.memory_deny == {"blob", "vault"}


@pytest.mark.parametrize(
    "env",
    [{"BACKEND": "memory", "MEMORY_DENY": "queue"}, {"BACKEND": "carrier-pigeon"}],
)
def test_unknown_choices_are_refused(env):
    with pytest.raises(ConfigError):
        Settings.from_env(env)
