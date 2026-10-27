"""Configuration from the environment (twelve-factor), validated once at start-up."""

from collections.abc import Mapping
from dataclasses import dataclass
from urllib.parse import urlparse

BACKENDS = ("azure", "memory")
DENIABLE = ("vault", "blob")
_LOG_LEVELS = ("DEBUG", "INFO", "WARNING", "ERROR")


class ConfigError(ValueError):
    """One or more settings are missing or malformed; the message lists all of them."""


@dataclass(frozen=True, slots=True)
class Settings:
    """Everything the app reads from the environment. None of it is a secret."""

    backend: str
    vault_url: str | None
    storage_url: str | None
    client_id: str | None
    container: str
    secret_name: str
    max_upload_bytes: int
    log_level: str
    memory_deny: frozenset[str]

    @classmethod
    def from_env(cls, env: Mapping[str, str]) -> "Settings":
        """Read and validate `env`; raise `ConfigError` naming every problem at once."""
        problems: list[str] = []
        backend = env.get("BACKEND", "azure")
        if backend not in BACKENDS:
            problems.append(f"BACKEND must be one of {BACKENDS}, got {backend!r}")
        vault_url = env.get("VAULT_URL") or None
        storage_url = env.get("STORAGE_URL") or None
        if backend == "azure":
            for name, value in (("VAULT_URL", vault_url), ("STORAGE_URL", storage_url)):
                if value is None or not _is_https_url(value):
                    problems.append(f"{name} must be an https URL when BACKEND=azure")
        max_upload_bytes = _positive_int(env, "MAX_UPLOAD_BYTES", 5_000_000, problems)
        log_level = env.get("LOG_LEVEL", "INFO").upper()
        if log_level not in _LOG_LEVELS:
            problems.append(f"LOG_LEVEL must be one of {_LOG_LEVELS}, got {log_level!r}")
        memory_deny = frozenset(part for part in env.get("MEMORY_DENY", "").split(",") if part)
        if not memory_deny <= set(DENIABLE):
            problems.append(f"MEMORY_DENY may only contain {DENIABLE}, got {sorted(memory_deny)}")
        if problems:
            raise ConfigError("; ".join(problems))
        return cls(
            backend=backend,
            vault_url=vault_url,
            storage_url=storage_url,
            client_id=env.get("AZURE_CLIENT_ID") or None,
            container=env.get("UPLOAD_CONTAINER", "uploads"),
            secret_name=env.get("SECRET_NAME", "partner-api-key"),
            max_upload_bytes=max_upload_bytes,
            log_level=log_level,
            memory_deny=memory_deny,
        )


def _is_https_url(value: str) -> bool:
    parsed = urlparse(value)
    return parsed.scheme == "https" and bool(parsed.netloc)


def _positive_int(env: Mapping[str, str], name: str, default: int, problems: list[str]) -> int:
    raw = env.get(name)
    if raw is None:
        return default
    if raw.isdecimal() and int(raw) > 0:
        return int(raw)
    problems.append(f"{name} must be a positive integer, got {raw!r}")
    return default
