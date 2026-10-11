"""The MCP server: tools that relay to the HammerForge bridge in the editor."""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
from pathlib import Path
from typing import Annotated, Any, Literal, Protocol

from mcp.server import MCPServer
from mcp.types import CallToolResult, ImageContent, TextContent
from pydantic import BaseModel, BeforeValidator, ConfigDict, Field

from hammerforge_mcp import __version__
from hammerforge_mcp.bridge import Bridge, BridgeError
from hammerforge_mcp.catalogue import PROTOCOL_ERRORS, SHAPES, TOOLS
from hammerforge_mcp.check import run_check
from hammerforge_mcp.prompts import PROMPTS

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


# Every Field comes before the BeforeValidator in one Annotated. A bound placed
# after it reaches the schema the agent sees as pydantic's own "gt" and "le",
# which JSON Schema does not know, so a client would never show it.

#: A finite number: NaN and Infinity are not JSON, and the editor refuses a frame
#: that carries one.
Number = Annotated[float, Field(allow_inf_nan=False), BeforeValidator(_not_a_bool)]
PositiveNumber = Annotated[
    float, Field(gt=0, allow_inf_nan=False), BeforeValidator(_not_a_bool)
]
#: How far hf_extrude_face pulls a face out: the editor's MAX_EXTRUDE.
ExtrudeDistance = Annotated[
    float, Field(gt=0, le=256, allow_inf_nan=False), BeforeValidator(_not_a_bool)
]
Vec3 = Annotated[
    list[Number],
    Field(min_length=3, max_length=3, description="[x, y, z] in metres"),
]
PositiveVec3 = Annotated[
    list[PositiveNumber],
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
FaceIndex = Annotated[int, Field(ge=0), BeforeValidator(_not_a_bool)]
#: A cylinder's or cone's sides from 5, a pyramid's from 3: the editor says which.
Sides = Annotated[
    int,
    Field(ge=3, le=64, description="Sides of a cylinder, cone or pyramid"),
    BeforeValidator(_not_a_bool),
]
MaterialRef = Annotated[
    str, Field(min_length=1, description="An id or a name from hf_get_materials")
]
Rotation = Annotated[Vec3, Field(description="Euler XYZ degrees, absolute")]


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


class BrushFocus(BaseModel):
    """Frame these brushes."""

    brush_ids: Annotated[list[str], Field(min_length=1)]


class BoundsFocus(BaseModel):
    """Frame this box."""

    bounds: Bounds


# A batch op's params, one model per change. The same names, types and defaults
# as the tool's own arguments, less operation_id; a test holds them together. A
# key the tool does not take is refused, not dropped.


class _Params(BaseModel):
    model_config = ConfigDict(extra="forbid")


class PlaceParams(_Params):
    size: PositiveVec3
    position: Annotated[Vec3, Field(description="The brush centre, [x, y, z]")]
    shape: Shape = "box"
    operation: Literal["union", "subtract"] = "union"
    snap: bool = True
    material: MaterialRef | None = None
    rotation_degrees: Rotation | None = None
    sides: Sides | None = None


class TransformParams(_Params):
    brush_id: BrushId
    position: Vec3 | None = None
    rotation_degrees: Vec3 | None = None
    snap: bool = True


class ResizeParams(_Params):
    brush_id: BrushId
    size: PositiveVec3
    snap: bool = True


class DeleteParams(_Params):
    brush_id: BrushId


class ExtrudeParams(_Params):
    brush_id: BrushId
    face: FaceSelector
    distance: ExtrudeDistance
    snap: bool = True


class AssignMaterialParams(_Params):
    brush_id: BrushId
    material: Annotated[str, Field(min_length=1)]
    faces: Annotated[list[FaceSelector] | None, Field(min_length=1)] = None


class SetSpawnParams(_Params):
    position: Vec3
    yaw_degrees: Number | None = None


EntityClass = Annotated[
    str, Field(min_length=1, description="A point entity class, such as light_point")
]
EntityProperties = Annotated[
    dict[str, Any] | None,
    Field(description="The class's own properties by name, such as {energy: 2}"),
]


class PlaceEntityParams(_Params):
    position: Vec3
    entity_class: EntityClass
    rotation_degrees: Rotation | None = None
    properties: EntityProperties = None
    preset: Annotated[str | None, Field(min_length=1)] = None
    name: Annotated[str | None, Field(min_length=1)] = None


class PlaceOp(_Params):
    tool: Literal["hf_place_brush"]
    params: PlaceParams


class TransformOp(_Params):
    tool: Literal["hf_transform_brush"]
    params: TransformParams


class ResizeOp(_Params):
    tool: Literal["hf_resize_brush"]
    params: ResizeParams


class DeleteOp(_Params):
    tool: Literal["hf_delete_brush"]
    params: DeleteParams


class ExtrudeOp(_Params):
    tool: Literal["hf_extrude_face"]
    params: ExtrudeParams


class AssignMaterialOp(_Params):
    tool: Literal["hf_assign_material"]
    params: AssignMaterialParams


class SetSpawnOp(_Params):
    tool: Literal["hf_set_spawn"]
    params: SetSpawnParams


class PlaceEntityOp(_Params):
    tool: Literal["hf_place_entity"]
    params: PlaceEntityParams


#: One change in a batch: a tool and the arguments it would take alone.
BatchOp = Annotated[
    PlaceOp
    | TransformOp
    | ResizeOp
    | DeleteOp
    | ExtrudeOp
    | AssignMaterialOp
    | SetSpawnOp
    | PlaceEntityOp,
    Field(discriminator="tool"),
]

#: Each batchable tool and the model its params are checked against.
BATCH_PARAMS: dict[str, type[BaseModel]] = {
    "hf_place_brush": PlaceParams,
    "hf_transform_brush": TransformParams,
    "hf_resize_brush": ResizeParams,
    "hf_delete_brush": DeleteParams,
    "hf_extrude_face": ExtrudeParams,
    "hf_assign_material": AssignMaterialParams,
    "hf_set_spawn": SetSpawnParams,
    "hf_place_entity": PlaceEntityParams,
}


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


def image_result(response: dict) -> CallToolResult:
    """A screenshot answer: the picture as an image block the model can see, and
    everything else about it, without the image data, as structured content."""
    result = to_result(response)
    structured = result.structured_content or {}
    shot = (structured.get("result") or {}).get("image")
    if not structured.get("ok") or not isinstance(shot, dict) or "data" not in shot:
        return result
    data = shot.pop("data")
    structured["result"]["image"] = shot
    image = ImageContent(
        type="image", data=data, mime_type=shot.get("mime_type", "image/png")
    )
    return CallToolResult(
        content=[image, TextContent(type="text", text=json.dumps(structured))],
        structured_content=structured,
        is_error=False,
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
        if log.isEnabledFor(logging.DEBUG):
            log.debug("%s %s", method, json.dumps(params))
        started = time.monotonic()
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
        took = (time.monotonic() - started) * 1000.0
        if response.get("ok"):
            log.info(
                "%s ok at revision %s in %.0f ms",
                method,
                response.get("revision"),
                took,
            )
        else:
            code = (response.get("error") or {}).get("code")
            log.info("%s refused: %s in %.0f ms", method, code, took)
        if method == "hf_viewport_screenshot":
            return image_result(response)
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
        material: MaterialRef | None = None,
        rotation_degrees: Rotation | None = None,
        sides: Sides | None = None,
        operation_id: OperationId = None,
    ) -> Annotated[CallToolResult, ToolOutput]:
        params: dict[str, Any] = {
            "size": size,
            "position": position,
            "shape": shape,
            "operation": operation,
            "snap": snap,
        }
        if material is not None:
            params["material"] = material
        if rotation_degrees is not None:
            params["rotation_degrees"] = rotation_degrees
        if sides is not None:
            params["sides"] = sides
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
        distance: ExtrudeDistance,
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

    @tool("hf_place_entity")
    async def hf_place_entity(
        position: Annotated[Vec3, Field(description="Where it stands, [x, y, z]")],
        entity_class: EntityClass,
        rotation_degrees: Rotation | None = None,
        properties: EntityProperties = None,
        preset: Annotated[str | None, Field(min_length=1)] = None,
        name: Annotated[str | None, Field(min_length=1)] = None,
        operation_id: OperationId = None,
    ) -> Annotated[CallToolResult, ToolOutput]:
        params: dict[str, Any] = {"entity_class": entity_class, "position": position}
        for key, value in (
            ("rotation_degrees", rotation_degrees),
            ("properties", properties),
            ("preset", preset),
            ("name", name),
        ):
            if value is not None:
                params[key] = value
        return await relay("hf_place_entity", params, operation_id)

    @tool("hf_get_entities")
    async def hf_get_entities() -> Annotated[CallToolResult, ToolOutput]:
        return await relay("hf_get_entities", {})

    @tool("hf_create_starter")
    async def hf_create_starter(
        operation_id: OperationId = None,
    ) -> Annotated[CallToolResult, ToolOutput]:
        return await relay("hf_create_starter", {}, operation_id)

    @tool("hf_bake")
    async def hf_bake(
        operation_id: OperationId = None,
    ) -> Annotated[CallToolResult, ToolOutput]:
        return await relay("hf_bake", {}, operation_id)

    @tool("hf_validate")
    async def hf_validate() -> Annotated[CallToolResult, ToolOutput]:
        return await relay("hf_validate", {})

    @tool("hf_viewport_screenshot")
    async def hf_viewport_screenshot(
        width: Annotated[int, Field(ge=64, le=1920)] = 1280,
        height: Annotated[int, Field(ge=64, le=1080)] = 720,
        focus: BrushFocus | BoundsFocus | None = None,
    ) -> Annotated[CallToolResult, ToolOutput]:
        params: dict[str, Any] = {"width": width, "height": height}
        if focus is not None:
            params["focus"] = focus.model_dump()
        return await relay("hf_viewport_screenshot", params)

    @tool("hf_batch")
    async def hf_batch(
        ops: Annotated[list[BatchOp], Field(min_length=1, max_length=100)],
        operation_id: OperationId = None,
    ) -> Annotated[CallToolResult, ToolOutput]:
        # What the caller sent, checked: no defaults filled in, no nulls.
        params = {
            "ops": [op.model_dump(exclude_unset=True, exclude_none=True) for op in ops]
        }
        return await relay("hf_batch", params, operation_id)

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

    for name, (title, description, make) in PROMPTS.items():
        server.prompt(name=name, title=title, description=description)(make)

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
    parser.add_argument(
        "--check",
        action="store_true",
        help="check the editor can be reached, print how to add this server to a "
        "client, and exit",
    )
    args = parser.parse_args(argv)
    if args.check:
        return run_check(args.project, args.discovery)

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
