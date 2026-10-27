"""The use cases the interfaces layer calls, bundled so the composition root can build them once."""

from dataclasses import dataclass

from secretless_app.application.check_health import CheckHealth
from secretless_app.application.save_upload import SaveUpload


@dataclass(frozen=True, slots=True)
class Services:
    """Every use case of the app."""

    check_health: CheckHealth
    save_upload: SaveUpload
