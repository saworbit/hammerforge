@tool
class_name HFShapeIcons
extends RefCounted
## HammerForge-owned brush-shape icons.
##
## Editor icon names vary between Godot releases, so the shape palette uses
## these SVG resources first and treats the editor theme as a fallback only.

const ICON_PATHS := {
	"BOX": "res://addons/hammerforge/icons/shapes/shape_box.svg",
	"CYLINDER": "res://addons/hammerforge/icons/shapes/shape_cylinder.svg",
	"SPHERE": "res://addons/hammerforge/icons/shapes/shape_sphere.svg",
	"CONE": "res://addons/hammerforge/icons/shapes/shape_cone.svg",
	"WEDGE": "res://addons/hammerforge/icons/shapes/shape_wedge.svg",
	"PYRAMID": "res://addons/hammerforge/icons/shapes/shape_pyramid.svg",
	"PRISM_TRI": "res://addons/hammerforge/icons/shapes/shape_prism_tri.svg",
	"PRISM_PENT": "res://addons/hammerforge/icons/shapes/shape_prism_pent.svg",
	"ELLIPSOID": "res://addons/hammerforge/icons/shapes/shape_ellipsoid.svg",
	"CAPSULE": "res://addons/hammerforge/icons/shapes/shape_capsule.svg",
	"TORUS": "res://addons/hammerforge/icons/shapes/shape_torus.svg",
	"TETRAHEDRON": "res://addons/hammerforge/icons/shapes/shape_tetrahedron.svg",
	"OCTAHEDRON": "res://addons/hammerforge/icons/shapes/shape_octahedron.svg",
	"DODECAHEDRON": "res://addons/hammerforge/icons/shapes/shape_dodecahedron.svg",
	"ICOSAHEDRON": "res://addons/hammerforge/icons/shapes/shape_icosahedron.svg",
}

static var _icon_cache: Dictionary = {}


static func get_icon(shape_key: String) -> Texture2D:
	if _icon_cache.has(shape_key):
		return _icon_cache[shape_key] as Texture2D
	var path := str(ICON_PATHS.get(shape_key, ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var icon := ResourceLoader.load(path) as Texture2D
	if icon:
		_icon_cache[shape_key] = icon
	return icon
