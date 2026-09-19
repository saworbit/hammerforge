@tool
extends RefCounted
class_name HFSurface

## What the player is standing on.
##
## Texturing a level is how a shipped game knows what is underfoot: the footstep
## sound, the impact decal, the bullet spark, whether a grenade bounces. All of
## it is a lookup against the surface a ray or a `move_and_slide()` just hit, and
## none of that information used to reach the baked collision, which was one
## `StaticBody3D` with no metadata at all (#707).
##
## The bake gives each material surface its own collision shape and writes the
## surface names onto the body, so the `shape` a hit reports names the material
## that was hit.
##
## **Why the shape and not the face.** `face_index` is the better answer and is
## not available: both `PhysicsDirectSpaceState3D.intersect_ray()` and
## `RayCast3D.get_collision_face_index()` return -1 on a `ConcavePolygonShape3D`
## under Jolt, which is this project's physics engine, whatever the class
## reference says. The shape index is what survives a hit, so that is what the
## bake made meaningful.
##
## A game does not need this file to read it -- the names are ordinary node
## metadata under `Baker.SURFACE_NAMES_META`. It exists so that reading them
## correctly is one call rather than a loop everyone writes slightly differently.

const NAMES_META := "hf_surface_names"

## What a hit on nothing identifiable answers. A name rather than an error, so a
## footstep table can hold a row for it.
const UNKNOWN := ""


## The material name at a hit, or `UNKNOWN` when the body cannot say.
##
## `shape_index` is the `shape` key of an `intersect_ray()` result, or
## `RayCast3D.get_collider_shape()`.
##
## A body baked in one of the per-brush collision modes carries no names, because
## there a shape is a brush and a brush has six faces with six materials. It
## answers `UNKNOWN` rather than naming one of the six.
static func material_at(body: Object, shape_index: int) -> String:
	if body == null or not is_instance_valid(body):
		return UNKNOWN
	if shape_index < 0 or not body.has_meta(NAMES_META):
		return UNKNOWN
	var names: PackedStringArray = body.get_meta(NAMES_META)
	if shape_index >= names.size():
		return UNKNOWN
	return names[shape_index]


## Every surface name on a body, in shape order. Empty when it carries none.
##
## For a game that wants to check its footstep table covers the level rather than
## finding a gap the first time somebody walks on the roof.
static func names_on(body: Object) -> PackedStringArray:
	if body == null or not is_instance_valid(body) or not body.has_meta(NAMES_META):
		return PackedStringArray()
	return body.get_meta(NAMES_META)


## The material name a ray is touching, in one call.
##
## The shape of the lookup a game actually writes: a `RayCast3D` pointed at the
## floor, asked what it is standing on. Answers `UNKNOWN` when it is touching
## nothing.
static func material_under(ray: RayCast3D) -> String:
	if ray == null or not is_instance_valid(ray) or not ray.is_colliding():
		return UNKNOWN
	return material_at(ray.get_collider(), ray.get_collider_shape())


## The material name a ray query hit, from the dictionary `intersect_ray()`
## returns. Answers `UNKNOWN` for an empty result.
static func material_from_hit(hit: Dictionary) -> String:
	if hit.is_empty():
		return UNKNOWN
	return material_at(hit.get("collider"), int(hit.get("shape", -1)))
