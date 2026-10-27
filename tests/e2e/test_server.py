"""Start the real gunicorn server with the in-memory backend and drive it over HTTP."""

import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from collections.abc import Iterator
from contextlib import closing

import pytest

pytestmark = pytest.mark.e2e


def _free_port() -> int:
    with closing(socket.socket()) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


class Server:
    def __init__(self, **env: str) -> None:
        self.port = _free_port()
        self.process = subprocess.Popen(
            [
                sys.executable,
                "-m",
                "gunicorn",
                "--bind",
                f"127.0.0.1:{self.port}",
                "--workers",
                "1",
                "secretless_app.interfaces.wsgi:create()",
            ],
            env={**os.environ, "BACKEND": "memory", **env},
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            try:
                self.request("GET", "/live")
                return
            except (urllib.error.URLError, ConnectionError, TimeoutError):
                time.sleep(0.1)
        self.process.kill()
        raise RuntimeError("server did not start")

    def request(self, method: str, path: str, body: bytes | None = None) -> tuple[int, dict[str, object]]:
        request = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", data=body, method=method)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as error:
            return error.code, json.load(error)

    def stop(self) -> str:
        self.process.terminate()  # gunicorn finishes in-flight requests on SIGTERM
        output, _ = self.process.communicate(timeout=120)
        return output


@pytest.fixture
def server() -> Iterator[Server]:
    instance = Server()
    yield instance
    instance.stop()


def test_the_lessons_curl_session_works_end_to_end(server):
    assert server.request("GET", "/health") == (200, {"status": "ok", "key_length": 14})
    assert server.request("POST", "/upload/hello.txt", b"hello") == (201, {"saved": "hello.txt"})


def test_removing_the_blob_role_is_refused_and_the_log_names_the_code():
    denied = Server(MEMORY_DENY="blob")
    status, body = denied.request("POST", "/upload/hello.txt", b"hello")
    output = denied.stop()
    assert status == 502
    assert body["code"] == "AuthorizationPermissionMismatch"
    log_lines = [json.loads(line) for line in output.splitlines() if line.startswith("{")]
    assert any(line.get("code") == "AuthorizationPermissionMismatch" and line["level"] == "ERROR" for line in log_lines)


def test_a_sigterm_stops_the_server_cleanly(server):
    server.request("GET", "/live")
    server.process.terminate()
    assert server.process.wait(timeout=120) == 0


def test_bad_configuration_stops_the_start_up_with_every_problem_named():
    process = subprocess.run(
        [sys.executable, "-m", "gunicorn", "--bind", "127.0.0.1:0", "secretless_app.interfaces.wsgi:create()"],
        env={**os.environ, "BACKEND": "azure", "VAULT_URL": "", "STORAGE_URL": ""},
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    assert process.returncode != 0
    assert "VAULT_URL" in process.stdout + process.stderr
