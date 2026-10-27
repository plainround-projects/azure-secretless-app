"""A secret value that cannot be printed or logged by accident."""


class Secret:
    """Holds a secret string; `repr`, `str` and formatting show a placeholder, `reveal` returns the value."""

    __slots__ = ("_value",)

    def __init__(self, value: str) -> None:
        """Wrap `value`."""
        self._value = value

    def reveal(self) -> str:
        """Return the secret itself; call it only where the value is used."""
        return self._value

    def __len__(self) -> int:
        """Return the length of the secret, which is safe to report."""
        return len(self._value)

    def __repr__(self) -> str:
        """Return a placeholder."""
        return "Secret(<redacted>)"

    __str__ = __repr__
