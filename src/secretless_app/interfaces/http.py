"""The Flask application: three routes and one place that maps named errors to HTTP statuses."""

import logging
import time

from flask import Flask, Response, jsonify, request
from werkzeug.exceptions import HTTPException, RequestEntityTooLarge

from secretless_app.application.services import Services
from secretless_app.domain.errors import AccessDeniedError, DependencyError, InvalidBlobNameError, UploadTooLargeError

LOGGER = logging.getLogger("secretless_app.http")


def create_app(services: Services, max_upload_bytes: int) -> Flask:
    """Build the app around `services`; uploads above `max_upload_bytes` are refused before they are read."""
    app = Flask("secretless_app")
    app.config["MAX_CONTENT_LENGTH"] = max_upload_bytes

    @app.get("/live")
    def live() -> Response:
        """Liveness: the process answers; touches no dependency, so a missing role never restarts the app."""
        return jsonify({"status": "alive"})

    @app.get("/health")
    def health() -> Response:
        """Read the partner key from the vault and report its length, never the key."""
        report = services.check_health.run()
        return jsonify({"status": "ok", "key_length": report.key_length})

    @app.post("/upload/<name>")
    def upload(name: str) -> tuple[Response, int]:
        """Write the request body to the uploads container under `name`."""
        saved = services.save_upload.run(name, request.get_data())
        return jsonify({"saved": saved.value}), 201

    _register_error_handlers(app)
    _register_request_log(app)
    return app


def _register_error_handlers(app: Flask) -> None:
    @app.errorhandler(InvalidBlobNameError)
    def invalid_name(error: InvalidBlobNameError) -> tuple[Response, int]:
        return jsonify({"error": "invalid_name", "detail": str(error)}), 400

    @app.errorhandler(UploadTooLargeError)
    def too_large(error: UploadTooLargeError) -> tuple[Response, int]:
        return jsonify({"error": "upload_too_large", "limit": error.limit}), 413

    @app.errorhandler(RequestEntityTooLarge)
    def body_too_large(error: RequestEntityTooLarge) -> tuple[Response, int]:
        return jsonify({"error": "upload_too_large", "limit": app.config["MAX_CONTENT_LENGTH"]}), 413

    @app.errorhandler(AccessDeniedError)
    def access_denied(error: AccessDeniedError) -> tuple[Response, int]:
        # The app's identity was refused, not the caller, so this is a bad gateway rather than a 403.
        # The full detail (caller object id, denied action) goes to the log, the code goes to the client.
        LOGGER.error(
            "access denied by %s",
            error.service,
            extra={"service": error.service, "code": error.code, "detail": error.detail},
        )
        return jsonify({"error": "upstream_access_denied", "service": error.service, "code": error.code}), 502

    @app.errorhandler(DependencyError)
    def dependency_failure(error: DependencyError) -> tuple[Response, int]:
        LOGGER.error(
            "dependency failure in %s",
            error.service,
            extra={"service": error.service, "code": error.code, "detail": error.detail},
        )
        return jsonify({"error": "upstream_failure", "service": error.service, "code": error.code}), 502

    @app.errorhandler(HTTPException)
    def http_error(error: HTTPException) -> tuple[Response, int]:
        return jsonify({"error": (error.name or "error").lower().replace(" ", "_")}), error.code or 500


def _register_request_log(app: Flask) -> None:
    @app.before_request
    def start_timer() -> None:
        request.environ["secretless.started"] = time.perf_counter()

    @app.after_request
    def log_request(response: Response) -> Response:
        started = request.environ.get("secretless.started", time.perf_counter())
        LOGGER.info(
            "request",
            extra={
                "method": request.method,
                "path": request.path,
                "status": response.status_code,
                "duration_ms": round((time.perf_counter() - started) * 1000, 1),
            },
        )
        return response
