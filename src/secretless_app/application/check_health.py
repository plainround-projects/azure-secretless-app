"""The health check: proves the vault role works by reading the partner key."""

from dataclasses import dataclass

from secretless_app.application.ports import SecretStore
from secretless_app.domain.health import HealthReport


@dataclass(frozen=True, slots=True)
class CheckHealth:
    """Read the partner key and report its length."""

    secrets: SecretStore
    secret_name: str

    def run(self) -> HealthReport:
        """Return the report, or raise `DependencyError` (`AccessDeniedError` when the role is missing)."""
        return HealthReport(key_length=len(self.secrets.get(self.secret_name)))
