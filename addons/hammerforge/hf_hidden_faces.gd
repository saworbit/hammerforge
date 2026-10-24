@tool
extends RefCounted
## Faces nobody will see (#1719): the look they wear in the editor, and what the
## bake, the `.map` files and the tools need to know about them.
##
## A Hidden face is a face type, `FaceData.FaceType.HIDDEN`. Every Hidden face of
## a level resolves to one material, its MaterialManager's, so the preview draws
## them all with one pattern and the bake knows them by it: a surface with that
## material is left out of the baked mesh, and so of the lightmap, while its
## triangles still go into the collision, so a floor stays solid from below.

## Set on the Hidden look, so the bake knows it whichever level made it.
const HIDDEN_META := "hf_hidden_face"
## What the material browser, the bake summary and a collision shape call it.
const LABEL := "Hidden"
## The texture name a `.map` export writes on a Hidden face.
const MAP_NAME := "skip"
## The texture names a `.map` import reads as Hidden, in lower case: the Quake
## family's names for a face the map compiler drops.
const MAP_NAMES := ["skip", "nodraw", "null", "common/nodraw", "common/caulk", "tools/toolsnodraw"]

## Plain stripes across the face, the same on every level and every angle, so a
## Hidden face never reads as a material. `shown` off draws nothing, which is how
## View Filters hides the Hidden faces of one level.
const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_back;

uniform bool shown = true;
uniform vec4 base_color : source_color = vec4(0.13, 0.14, 0.17, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.78, 0.62, 0.22, 1.0);
uniform float stripes_per_metre = 2.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (!shown) {
		discard;
	}
	float along = fract((world_position.x + world_position.y + world_position.z) * stripes_per_metre);
	ALBEDO = mix(base_color.rgb, stripe_color.rgb, step(0.75, along));
}
"""

static var _shader: Shader = null
static var _shared: ShaderMaterial = null


## The look of a level's Hidden faces: its material manager's own, so one level's
## can be hidden from view and another's not, or a shared one for a face with no
## manager, such as one on its own in a test.
static func material_for(material_manager: Object) -> Material:
	if material_manager != null and material_manager.has_method("hidden_face_material"):
		return material_manager.hidden_face_material()
	if _shared == null:
		_shared = make_material()
	return _shared


static func make_material() -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.resource_name = LABEL
	material.set_meta(HIDDEN_META, true)
	return material


## The Hidden swatch's picture: the pattern the faces wear.
static func swatch_texture(size: int = 64) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var base := Color(0.13, 0.14, 0.17)
	var stripe := Color(0.78, 0.62, 0.22)
	for y in size:
		for x in size:
			var along := fposmod(float(x + y) / float(size) * 4.0, 1.0)
			image.set_pixel(x, y, stripe if along >= 0.75 else base)
	return ImageTexture.create_from_image(image)


static func is_hidden_material(material: Variant) -> bool:
	return material is Material and (material as Material).has_meta(HIDDEN_META)


## Draw the Hidden faces that wear `material`, or draw none of them.
static func set_shown(material: Material, shown: bool) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("shown", shown)


static func has_hidden_surface(mesh: Mesh) -> bool:
	if mesh == null:
		return false
	for i in mesh.get_surface_count():
		if is_hidden_material(mesh.surface_get_material(i)):
			return true
	return false


## `mesh` without its Hidden surfaces: `mesh` itself when it has none, and null
## when every surface is Hidden.
static func without_hidden(mesh: Mesh) -> Mesh:
	if not has_hidden_surface(mesh):
		return mesh
	var out := ArrayMesh.new()
	for i in mesh.get_surface_count():
		var material := mesh.surface_get_material(i)
		if is_hidden_material(material):
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(i))
		out.surface_set_material(out.get_surface_count() - 1, material)
	return out if out.get_surface_count() > 0 else null


## How many Hidden faces `brushes` hold and their area in square metres: what a
## bake leaves out, as its summary says.
static func count(brushes: Array) -> Dictionary:
	var faces := 0
	var area := 0.0
	for brush in brushes:
		if not (is_instance_valid(brush) and brush is Node3D and brush.has_method("get_faces")):
			continue
		var basis: Basis = (brush as Node3D).global_transform.basis
		for face in brush.get_faces():
			if face != null and face.is_hidden():
				faces += 1
				area += polygon_area(basis, face.local_verts)
	return {"faces": faces, "area": area}


## The area of the polygon `corners` once `basis` has placed it.
static func polygon_area(basis: Basis, corners: PackedVector3Array) -> float:
	var twice := Vector3.ZERO
	for i in range(1, corners.size() - 1):
		var a := basis * (corners[i] - corners[0])
		var b := basis * (corners[i + 1] - corners[0])
		twice += a.cross(b)
	return twice.length() * 0.5


## What the bake summary says it left out, or "" when it left out nothing.
static func summary(counted: Dictionary) -> String:
	var faces := int(counted.get("faces", 0))
	if faces <= 0:
		return ""
	return (
		"left out %d Hidden face%s, %.1f square metres of mesh and lightmap"
		% [faces, "" if faces == 1 else "s", float(counted.get("area", 0.0))]
	)


static func is_map_name(texture: String) -> bool:
	return MAP_NAMES.has(texture.strip_edges().to_lower())
