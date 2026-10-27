import json
import logging

from secretless_app.infrastructure.logging import JsonFormatter, configure_logging
from secretless_app.infrastructure.memory_adapters import DEMO_SECRET_VALUE
from secretless_app.infrastructure.settings import Settings
from secretless_app.infrastructure.wiring import build_services


def test_a_record_becomes_one_json_line_with_its_extra_fields_on_top():
    record = logging.LogRecord("app", logging.ERROR, __file__, 1, "access denied by %s", ("blob",), None)
    record.code = "AuthorizationPermissionMismatch"
    line = JsonFormatter().format(record)
    payload = json.loads(line)
    assert "\n" not in line
    assert payload["level"] == "ERROR"
    assert payload["msg"] == "access denied by blob"
    assert payload["code"] == "AuthorizationPermissionMismatch"
    assert payload["ts"].endswith("+00:00")


def test_an_exception_is_included_as_text():
    try:
        raise ValueError("boom")
    except ValueError:
        import sys

        record = logging.LogRecord("app", logging.ERROR, __file__, 1, "failed", (), sys.exc_info())
    assert "ValueError: boom" in json.loads(JsonFormatter().format(record))["exc"]


def test_configuring_twice_leaves_one_handler(capsys):
    configure_logging("INFO")
    configure_logging("DEBUG")
    assert len(logging.getLogger().handlers) == 1
    assert logging.getLogger().level == logging.DEBUG
    configure_logging("INFO")


def test_the_memory_backend_wires_a_working_demo_vault():
    services = build_services(Settings.from_env({"BACKEND": "memory"}))
    assert services.check_health.run().key_length == len(DEMO_SECRET_VALUE)


def test_the_azure_backend_wires_without_contacting_azure():
    settings = Settings.from_env(
        {
            "VAULT_URL": "https://kv-test.vault.azure.net",
            "STORAGE_URL": "https://sttest.blob.core.windows.net",
        }
    )
    services = build_services(settings)
    assert services.check_health.secret_name == "partner-api-key"
