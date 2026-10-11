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
from pydantic import BaseModel, BeforeValidator, Field

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


def _not_a_bool(value: Any) -> Any:
    # JSON true is not a coordinate, though pydantic would read it as 1.0.
    if isinstance(value, bool):
        raise ValueError("a number, not true or false")
    return value


#: A finite number: NaN and Infinity are not JSON, and the editor refuses a frame
#: that carries one.
Number = Annotated[float, BeforeValidator(_not_a_bool), Field(allow_inf_nan=False)]
Vec3 = Annotated[
    list[Number],
    Field(min_length=3, max_length=3, description="[x, y, z] in metres"),
]
PositiveVec3 = Annotated[
    list[Annotated[Number, Field(gt=0)]],
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


BrushId = Annotated[
    str, Field(min_length=1, description="A brush_id from hf_get_brushes or a change")
]
Side = Literal["+x", "-x", "+y", "-y", "+z", "-z"]
FaceIndex = Annotated[int, BeforeValidator(_not_a_bool), Field(ge=0)]


class NormalSelector(BaseModel):
    """The face whose world normal points most nearly along `normal`."""

    normal: Vec3


FaceSelector = Annotated[
    FaceIndex | Side | NormalSelector,
    Field(
        description=(
            "A face index, a world side such as '+y', or {normal: [x, y, z]}. "
            "Box faces are stored +X, -X, +Y, -Y, +Z, -Z."
        )
    ),
]


class Bounds(BaseModel):
    """A world-space box: keep brushes that overlap it."""

    min: Vec3
    max: Vec3


def _face(selector: Any) -> Any:
    return selector.model_dump() if isinstance(selector, BaseModel) else selector


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
    #: The id a change went with. Send it again to retry without running twice.
    operation_id: str | None = None
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
    if response.get("operation_id"):
        structured["operation_id"] = str(response["operation_id"])
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

    @tool("hf_get_brushes")
    async def hf_get_brushes(
        brush_ids: list[str] | None = None,
        bounds: Bounds | None = None,
        include_faces: bool = True,
        limit: Annotated[int, Field(ge=1, le=2000)] = 200,
    ) -> Annotated[CallToolResult, ToolOutput]:
        params: dict[str, Any] = {"include_faces": include_faces, "limit": limit}
        if brush_ids is not None:
            params["brush_ids"] = brush_ids
        if bounds is not None:
            params["bounds"] = bounds.model_dump()
        return await relay("hf_get_brushes", params)

    @tool("hf_get_materials")
    async def hf_get_materials() -> Annotated[CallToolResult, ToolOutput]:
        return await relay("hf_get_materials", {})

    @tool("hf_transform_brush")
    async def hf_transform_brush(
        brush_id: BrushId,
        position: Annotated[Vec3 | None, Field(description="The new centre")] = None,
        rotation_degrees: Annotated[
            Vec3 | None, Field(description="Euler XYZ degrees, absolute")
        ] = None,
        snap: bool = True,
        operation_id: OperationId = None,
    ) -> Annotated[CallToolResult, ToolOutput]:
        params: dict[str, Any] = {"brush_id": brush_id, "snap": snap}
        if position is not None:
            params["position"] = position
        if rotation_degrees is not None:
            params["rotation_degrees"] = rotation_degrees
        return await relay("hf_transform_brush", params, operation_id)

    @tool("hf_resize_brush")
    async def hf_resize_brush(
        brush_id: BrushId,
        size: PositiveVec3,
        snap: bool = True,
        operation_id: OperationId = None,
    ) -> Annotated[CallToolResult, ToolOutput]:
        params = {"brush_id": brush_id, "size": size, "snap": snap}
        return await relay("hf_resize_brush", params, operation_id)

    @tool("hf_delete_brush")
    async def hf_delete_brush(
        brush_id: BrushId, operation_id: OperationId = None
    ) -> Annotated[CallToolResult, ToolOutput]:
        return await relay("hf_delete_brush", {"brush_id": brush_id}, operation_id)

    @tool("hf_extrude_face")
    async def hf_extrude_face(
        brush_id: BrushId,
        face: FaceSelector,
        distance: Annotated[Number, Field(gt=0, le=256)],
        snap: bool = True,
        operation_id: OperationId = None,
    ) -> Annotated[CallToolResult, ToolOutput]:
        params = {
            "brush_id": brush_id,
            "face": _face(face),
            "distance": distance,
            "snap": snap,
        }
        return await relay("hf_extrude_face", params, operation_id)

    @tool("hf_assign_material")
    async def hf_assign_material(
        brush_id: BrushId,
        material: Annotated[
            str,
            Field(min_length=1, description="An id or a name from hf_get_materials"),
        ],
        faces: Annotated[
            list[FaceSelector] | None,
            Field(min_length=1, description="Only these faces; all faces if absent"),
        ] = None,
        operation_id: OperationId = None,
    ) -> Annotated[CallToolResult, ToolOutput]:
        params: dict[str, Any] = {"brush_id": brush_id, "material": material}
        if faces is not None:
            params["faces"] = [_face(face) for face in faces]
        return await relay("hf_assign_material", params, operation_id)

    @tool("hf_set_spawn")
    async def hf_set_spawn(
        position: Annotated[
            Vec3, Field(description="The floor point the player's feet stand on")
        ],
        yaw_degrees: Number | None = None,
        operation_id: OperationId = None,
    ) -> Annotated[CallToolResult, ToolOutput]:
        params: dict[str, Any] = {"position": position}
        if yaw_degrees is not None:
            params["yaw_degrees"] = yaw_degrees
        return await relay("hf_set_spawn", params, operation_id)

    @tool("hf_create_starter")
    async def hf_create_starter(
        operation_id: OperationId = None,
    ) -> Annotated[CallToolResult, ToolOutput]:
        return await relay("hf_create_starter", {}, operation_id)

    @tool("hf_undo")
    async def hf_undo(
        operation_id: OperationId = None,
    ) -> Annotated[CallToolResult, ToolOutput]:
        return await relay("hf_undo", {}, operation_id)

    @tool("hf_redo")
    async def hf_redo(
        operation_id: OperationId = None,
    ) -> Annotated[CallToolResult, ToolOutput]:
        return await relay("hf_redo", {}, operation_id)

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
        "--discovery",
        type=Path,
        default=os.environ.get("HAMMERFORGE_MCP_DISCOVERY") or None,
        help="the bridge's discovery file, when it is not the project's own",
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
    build_server(Bridge(args.project, discovery=args.discovery)).run("stdio")
    return 0
