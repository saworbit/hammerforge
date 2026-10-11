"""The MCP server: tools that relay to the HammerForge bridge in the editor."""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from pathlib import Path
from typing import Annotated, Any, Literal, Protocol

from mcp.server import MCPServer
from mcp.types import CallToolResult, TextContent
from pydantic import BaseModel, Field

from hammerforge_mcp import __version__
from hammerforge_mcp.bridge import Bridge, BridgeError
from hammerforge_mcp.catalogue import PROTOCOL_ERRORS, SHAPES, TOOLS

log = logging.getLogger("hammerforge_mcp")

INSTRUCTIONS = (
    "Drives a live HammerForge level in the Godot editor. Call hf_get_status "
    "first. Every change is one undo step the user can see in the editor's "
    "history. If a change answers target_changed, the user has opened another "
    "scene or level: call hf_get_status to work on that one."
)

Vec3 = Annotated[
    list[float],
    Field(min_length=3, max_length=3, description="[x, y, z] in metres"),
]
PositiveVec3 = Annotated[
    list[Annotated[float, Field(gt=0)]],
    Field(min_length=3, max_length=3, description="[x, y, z] full extents in metres"),
]
# The same names as BrushShape in level_root.gd, less CUSTOM.
Shape = Literal[SHAPES]
OperationId = Annotated[
    str | None,
    Field(
        pattern=r"^[A-Za-z0-9._:-]{1,128}$",
        description=(
            "Your own id for this change. Send the same one again to retry safely."
        ),
    ),
]


class ErrorBody(BaseModel):
    code: str
    message: str
    details: dict[str, Any] = {}


class ToolOutput(BaseModel):
    """Every tool's structured answer: ok with a result, or not ok with an error."""

    ok: bool
    revision: int | None = None
    target_id: str | None = None
    replayed: bool = False
    result: dict[str, Any] | None = None
    error: ErrorBody | None = None


class BridgeLike(Protocol):
    async def call(
        self,
        method: str,
        params: dict,
        *,
        mutating: bool,
        timeout: float,
        operation_id: str | None = None,
    ) -> dict: ...


def to_result(response: dict) -> CallToolResult:
    """The editor's response as an MCP tool result.

    A refusal from the level (no such brush, bad size) is a normal result with
    ok false, so the agent reads it and adjusts. A failure of the bridge itself
    is an error result.
    """
    structured: dict[str, Any] = {
        "ok": bool(response.get("ok")),
        "revision": response.get("revision"),
        "target_id": response.get("target_id"),
        "replayed": bool(response.get("replayed", False)),
    }
    if structured["ok"]:
        structured["result"] = response.get("result") or {}
        is_error = False
    else:
        error = response.get("error") or {}
        structured["error"] = {
            "code": str(error.get("code", "internal_error")),
            "message": str(error.get("message", "")),
            "details": error.get("details") or {},
        }
        is_error = structured["error"]["code"] in PROTOCOL_ERRORS
    return CallToolResult(
        content=[TextContent(type="text", text=json.dumps(structured))],
        structured_content=structured,
        is_error=is_error,
    )


def error_result(
    code: str, message: str, details: dict | None = None
) -> CallToolResult:
    structured = {
        "ok": False,
        "error": {"code": code, "message": message, "details": details or {}},
    }
    return CallToolResult(
        content=[TextContent(type="text", text=f"{code}: {message}")],
        structured_content=structured,
        is_error=True,
    )


def build_server(bridge: BridgeLike) -> MCPServer:
    server = MCPServer(
        name="hammerforge",
        title="HammerForge",
        version=__version__,
        instructions=INSTRUCTIONS,
    )

    async def relay(
        method: str, params: dict, operation_id: str | None = None
    ) -> CallToolResult:
        spec = TOOLS[method]
        try:
            response = await bridge.call(
                method,
                params,
                mutating=spec.mutating,
                timeout=spec.timeout,
                operation_id=operation_id,
            )
        except BridgeError as exc:
            log.warning("%s failed: %s: %s", method, exc.code, exc)
            return error_result(exc.code, str(exc), exc.details)
        return to_result(response)

    def tool(name: str):
        spec = TOOLS[name]
        return server.tool(
            name=spec.name,
            title=spec.title,
            description=spec.description,
            annotations=spec.annotations,
        )

    @tool("hf_get_status")
    async def hf_get_status() -> Annotated[CallToolResult, ToolOutput]:
        return await relay("hf_get_status", {})

    @tool("hf_place_brush")
    async def hf_place_brush(
        size: PositiveVec3,
        position: Annotated[Vec3, Field(description="The brush centre, [x, y, z]")],
        shape: Shape = "box",
        operation: Literal["union", "subtract"] = "union",
        snap: bool = True,
        operation_id: OperationId = None,
    ) -> Annotated[CallToolResult, ToolOutput]:
        params = {
            "size": size,
            "position": position,
            "shape": shape,
            "operation": operation,
            "snap": snap,
        }
        return await relay("hf_place_brush", params, operation_id)

    return server


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="hammerforge-mcp",
        description="Let an MCP agent drive a live HammerForge level in Godot.",
    )
    parser.add_argument(
        "--project",
        type=Path,
        default=Path(os.environ.get("HAMMERFORGE_PROJECT") or Path.cwd()),
        help="the Godot project folder, the one with project.godot in it",
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
    )
    parser.add_argument("--log-file", type=Path, help="also write the log here")
    parser.add_argument("--version", action="version", version=__version__)
    args = parser.parse_args(argv)

    # stdout carries the MCP protocol. Everything else goes to stderr.
    handlers: list[logging.Handler] = [logging.StreamHandler(sys.stderr)]
    if args.log_file:
        handlers.append(logging.FileHandler(args.log_file, encoding="utf-8"))
    logging.basicConfig(
        level=args.log_level,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        handlers=handlers,
    )
    log.info("hammerforge-mcp %s for %s", __version__, args.project)
    build_server(Bridge(args.project)).run("stdio")
    return 0
