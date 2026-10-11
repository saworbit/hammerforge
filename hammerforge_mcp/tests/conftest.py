"""A fake editor listener on a real loopback socket, for the bridge tests."""

from __future__ import annotations

import asyncio
import json
import os
from collections.abc import Callable
from pathlib import Path

import pytest

from hammerforge_mcp.framing import MAX_REQUEST_BYTES, encode_frame, read_frame

TOKEN = "ab" * 32


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


def make_project(root: Path) -> Path:
    (root / ".godot").mkdir(parents=True, exist_ok=True)
    (root / "project.godot").write_text("config_version=5\n", encoding="utf-8")
    return root


def write_discovery(project: Path, port: int, *, pid: int | None = None) -> None:
    body = {
        "bridge_version": 1,
        "port": port,
        "pid": os.getpid() if pid is None else pid,
        "token": TOKEN,
        "project_path": str(project),
        "hammerforge_version": "0.3.2",
    }
    (project / ".godot" / "hammerforge_mcp.json").write_text(
        json.dumps(body), encoding="utf-8"
    )


#: A responder that returns this keeps the connection open and never answers.
HOLD = object()

Responder = Callable[[dict], "dict | object | None"]


def ok(request: dict, result: dict | None = None, target: str = "1:2:3") -> dict:
    return {
        "type": "response",
        "id": request["id"],
        "ok": True,
        "result": result or {},
        "revision": 5,
        "target_id": target,
        "replayed": False,
    }


def failed(request: dict, code: str, target: str = "1:2:3") -> dict:
    return {
        "type": "response",
        "id": request["id"],
        "ok": False,
        "error": {"code": code, "message": code, "details": {}},
        "revision": 5,
        "target_id": target,
    }


class FakeListener:
    """Says welcome to the right token, then answers with `responder`.

    A responder that returns None closes the connection without answering,
    which is how a lost response looks from the client's side. One that returns
    HOLD never answers and keeps the connection open, like a long bake.
    """

    def __init__(self, project: Path, responder: Responder | None = None) -> None:
        self.project = project
        self.responder: Responder = responder or (lambda request: ok(request))
        self.hellos: list[dict] = []
        self.requests: list[dict] = []
        self.connections = 0
        self._server: asyncio.base_events.Server | None = None
        self._release = asyncio.Event()

    async def start(self) -> FakeListener:
        self._server = await asyncio.start_server(self._client, "127.0.0.1", 0)
        port = self._server.sockets[0].getsockname()[1]
        write_discovery(self.project, port)
        return self

    async def stop(self) -> None:
        self._release.set()
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()

    async def _client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        self.connections += 1
        try:
            hello = await read_frame(reader, MAX_REQUEST_BYTES)
            self.hellos.append(hello)
            if hello.get("token") != TOKEN:
                error = {"code": "auth_failed", "message": "no", "details": {}}
                writer.write(encode_frame({"type": "error", "error": error}))
                await writer.drain()
                return
            writer.write(
                encode_frame({"type": "welcome", "bridge_version": 1, "editor_pid": 1})
            )
            await writer.drain()
            while True:
                request = await read_frame(reader, MAX_REQUEST_BYTES)
                self.requests.append(request)
                response = self.responder(request)
                if response is None:
                    return
                if response is HOLD:
                    await self._release.wait()
                    return
                writer.write(encode_frame(response, 1 << 24))
                await writer.drain()
        except (asyncio.IncompleteReadError, ConnectionError):
            return
        finally:
            writer.close()
