"""The gunicorn entry point: `gunicorn "secretless_app.interfaces.wsgi:create()"`."""

import os

from flask import Flask

from secretless_app.infrastructure.logging import configure_logging
from secretless_app.infrastructure.settings import Settings
from secretless_app.infrastructure.wiring import build_services
from secretless_app.interfaces.http import create_app


def create() -> Flask:
    """Read the settings from the environment, wire the adapters and return the app."""
    settings = Settings.from_env(os.environ)
    configure_logging(settings.log_level)
    return create_app(build_services(settings), settings.max_upload_bytes)
