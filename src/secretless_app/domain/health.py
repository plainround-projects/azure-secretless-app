"""What a successful health check reports."""

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class HealthReport:
    """The vault answered: the secret exists and has `key_length` characters. The key itself is never reported."""

    key_length: int
