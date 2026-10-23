@tool
extends RefCounted
## A top down plan of a level, drawn from its brushes rather than rendered, so it
## draws in a headless editor and in CI (#1705).
##
## Each brush's footprint is the outline of the part of it inside a height band,
## seen from above: the hull of its corners in the band and of the points where
## its edges cross the band's top and bottom. A convex brush's outline is exactly
## that hull. Solid brushes are filled, cut brushes hatched, entities are symbols
## by kind, I/O wires thin lines, and cordons dashed boxes, with a scale bar and
## an arrow to -Z, the way a spawn at yaw 0 faces.
##
## The plan is in metres on the ground: its x is world X and its y world Z, so -Z
## is up the page. `svg()` writes it as text with no dependency. `png()` fills the
## same polygons on the CPU into an `Image`, a scanline at a time.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const DraftEntity = preload("draft_entity.gd")
const HFBrushEntity = preload("hf_brush_entity.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFSolidMeasure = preload("hf_solid_measure.gd")
const HFObjectFilter = preload("hf_object_filter.gd")

## What each part of a plan is drawn in.
const COLORS := {
	"background": Color(1.0, 1.0, 1.0),
	"solid": Color(0.66, 0.69, 0.74),
	"outline": Color(0.13, 0.14, 0.16),
	"cut": Color(0.82, 0.27, 0.22),
	"brush_entity": Color(0.55, 0.36, 0.86),
	"wire": Color(0.92, 0.66, 0.1),
	"cordon": Color(0.25, 0.55, 0.95),
	"spawn": Color(0.18, 0.66, 0.3),
	"light": Color(0.98, 0.78, 0.12),
	"trigger": Color(0.6, 0.35, 0.9),
	"door": Color(0.5, 0.33, 0.16),
	"entity": Color(0.35, 0.35, 0.38),
}
## Room around the level, in metres.
const MARGIN := 1.0
## An entity's symbol's radius, in metres in the SVG and pixels in the PNG.
const SYMBOL_METRES := 0.3
const SYMBOL_PIXELS := 4
## A cut's hatching, in pixels: a stripe this many wide in every this many.
const HATCH_PERIOD := 8
const HATCH_WIDTH := 3


## The plan's pieces between `y_min` and `y_max`: `solids` and `cuts`, footprints
## as PackedVector2Array; `brush_entities`, outlines of brushes tied to a class;
## `entities`, `{at, kind, name}`; `wires`, `[from, to]`; `cordons`, Rect2s;
## `labels`, `{at, text}`; and `bounds`, all of it. `rule` is a brush filter as
## `HFObjectFilter` reads one, with any material already a palette slot.
static func shapes(
	root: Node, y_min: float = -INF, y_max: float = INF, rule: Dictionary = {}
) -> Dictionary:
	var data := {
		"solids": [],
		"cuts": [],
		"brush_entities": [],
		"entities": [],
		"wires": [],
		"cordons": [],
		"labels": [],
		"bounds": Rect2(),
	}
	var points := PackedVector2Array()
	for brush in root._iter_managed_brush_nodes():
		if brush.get_parent() == root.committed_node or not brush.is_visible_in_tree():
			continue
		if not rule.is_empty() and not HFObjectFilter.brush_passes(root, brush, rule):
			continue
		var outline := footprint(HFSolidMeasure.world_faces(brush), y_min, y_max)
		if outline.size() < 3:
			continue
		var kind := "solids"
		if HFBrushEntity.entity_class(brush) != "":
			kind = "brush_entities"
		elif brush.operation == CSGShape3D.OPERATION_SUBTRACTION:
			kind = "cuts"
		data[kind].append(outline)
		points.append_array(outline)
		var centre := Vector2.ZERO
		for corner in outline:
			centre += corner
		data["labels"].append({"at": centre / outline.size(), "text": str(brush.name)})
	var at_of: Dictionary = {}
	if root.entities_node:
		for node in root.entities_node.get_children():
			if not (node is DraftEntity) or not (node as Node3D).is_visible_in_tree():
				continue
			var spot := (node as Node3D).global_position
			if spot.y < y_min or spot.y > y_max:
				continue
			var at := Vector2(spot.x, spot.z)
			var named := str(node.get_meta("entity_name", ""))
			data["entities"].append(
				{"at": at, "kind": kind_of(str(node.entity_class)), "name": named}
			)
			points.append(at)
			at_of[node] = at
	if root.entity_system:
		var index: Dictionary = root.entity_system.build_name_index()
		for connection in root.entity_system.get_all_connections():
			var source: Variant = connection.get("source")
			if not at_of.has(source):
				continue
			for target in index.get(str(connection.get("target_name", "")), []):
				if at_of.has(target):
					data["wires"].append([at_of[source], at_of[target]])
	# A level always has a cordon box; it means something only when cordons are on.
	var cordons: Array = root.get_cordon_regions() if root.cordon_enabled else []
	for region in cordons:
		var box := Rect2(region.position.x, region.position.z, region.size.x, region.size.z)
		data["cordons"].append(box)
		points.append(box.position)
		points.append(box.end)
	data["bounds"] = _bounds(points)
	return data


## The outline seen from above of the part of a convex solid, given by its world
## faces, between `y_min` and `y_max`. Empty when none of it is in the band.
static func footprint(faces: Array, y_min: float, y_max: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for face in faces:
		var ring := HFSolidMeasure.ring(face)
		for i in ring.size():
			var a := ring[i]
			var b := ring[(i + 1) % ring.size()]
			if a.y >= y_min and a.y <= y_max:
				points.append(Vector2(a.x, a.z))
			for level in [y_min, y_max]:
				if is_finite(level) and (a.y - level) * (b.y - level) < 0.0:
					var cross := a.lerp(b, (level - a.y) / (b.y - a.y))
					points.append(Vector2(cross.x, cross.z))
	if points.size() < 3:
		return PackedVector2Array()
	var hull := Geometry2D.convex_hull(points)
	# The hull comes back closed, its first point again at the end.
	if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.remove_at(hull.size() - 1)
	return hull if hull.size() >= 3 else PackedVector2Array()


## The symbol an entity class gets.
static func kind_of(entity_class: String) -> String:
	var lower := entity_class.to_lower()
	for kind in ["spawn", "light", "trigger", "door"]:
		if lower.contains(kind):
			return kind
	if lower.contains("player_start") or lower.contains("info_player"):
		return "spawn"
	return "entity"


## Write `root`'s plan as `<base>.svg` and `<base>.png`. OK, or the first error.
static func write_files(
	root: Node,
	base: String,
	y_min: float = -INF,
	y_max: float = INF,
	size: int = 1024,
	labels: bool = false
) -> int:
	var data := shapes(root, y_min, y_max)
	var file := FileAccess.open(base + ".svg", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(svg(data, labels))
	file.close()
	return image(data, size).save_png(base + ".png")


static func _bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2(-1.0, -1.0, 2.0, 2.0)
	var box := Rect2(points[0], Vector2.ZERO)
	for point in points:
		box = box.expand(point)
	return box


# ---------------------------------------------------------------------------
# SVG
# ---------------------------------------------------------------------------


## The plan as SVG text, in metres: one user unit is a metre, x is world X and y
## world Z.
static func svg(data: Dictionary, labels: bool = false) -> String:
	var view: Rect2 = (data["bounds"] as Rect2).grow(MARGIN)
	var line_width := maxf(view.size.x, view.size.y) / 400.0
	var out := PackedStringArray()
	(
		out
		. append(
			(
				'<svg xmlns="http://www.w3.org/2000/svg" viewBox="%s %s %s %s" width="%smm" height="%smm">'
				% [
					_n(view.position.x),
					_n(view.position.y),
					_n(view.size.x),
					_n(view.size.y),
					_n(view.size.x * 10.0),
					_n(view.size.y * 10.0)
				]
			)
		)
	)
	(
		out
		. append(
			(
				'<defs><pattern id="hatch" patternUnits="userSpaceOnUse" width="0.4" height="0.4" patternTransform="rotate(45)"><line x1="0" y1="0" x2="0" y2="0.4" stroke="%s" stroke-width="0.12"/></pattern></defs>'
				% _hex("cut")
			)
		)
	)
	out.append(
		(
			'<rect x="%s" y="%s" width="%s" height="%s" fill="%s"/>'
			% [
				_n(view.position.x),
				_n(view.position.y),
				_n(view.size.x),
				_n(view.size.y),
				_hex("background")
			]
		)
	)
	for outline in data["solids"]:
		out.append(_polygon("solid", outline, _hex("solid"), _hex("outline"), line_width))
	for outline in data["brush_entities"]:
		out.append(
			_polygon("brush-entity", outline, "none", _hex("brush_entity"), line_width * 2.0)
		)
	for outline in data["cuts"]:
		out.append(_polygon("cut", outline, "url(#hatch)", _hex("cut"), line_width))
	for box in data["cordons"]:
		(
			out
			. append(
				(
					'<rect class="cordon" x="%s" y="%s" width="%s" height="%s" fill="none" stroke="%s" stroke-width="%s" stroke-dasharray="%s %s"/>'
					% [
						_n(box.position.x),
						_n(box.position.y),
						_n(box.size.x),
						_n(box.size.y),
						_hex("cordon"),
						_n(line_width * 2.0),
						_n(line_width * 8.0),
						_n(line_width * 5.0)
					]
				)
			)
		)
	for wire in data["wires"]:
		out.append(
			(
				'<line class="wire" x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="%s"/>'
				% [
					_n(wire[0].x),
					_n(wire[0].y),
					_n(wire[1].x),
					_n(wire[1].y),
					_hex("wire"),
					_n(line_width)
				]
			)
		)
	for entity in data["entities"]:
		(
			out
			. append(
				(
					'<circle class="entity %s" cx="%s" cy="%s" r="%s" fill="%s" stroke="%s" stroke-width="%s"/>'
					% [
						entity["kind"],
						_n(entity["at"].x),
						_n(entity["at"].y),
						_n(SYMBOL_METRES),
						_hex(entity["kind"]),
						_hex("outline"),
						_n(line_width)
					]
				)
			)
		)
	if labels:
		var size := maxf(view.size.x, view.size.y) / 80.0
		for label in data["labels"]:
			out.append(_text(label["at"], label["text"], size))
		for entity in data["entities"]:
			if entity["name"] != "":
				out.append(
					_text(entity["at"] + Vector2(0.0, -SYMBOL_METRES * 2.0), entity["name"], size)
				)
	out.append_array(_svg_scale_and_arrow(view, line_width))
	out.append("</svg>")
	return "\n".join(out) + "\n"


static func _polygon(
	kind: String, outline: PackedVector2Array, fill: String, stroke: String, width: float
) -> String:
	var points := PackedStringArray()
	for corner in outline:
		points.append("%s,%s" % [_n(corner.x), _n(corner.y)])
	return (
		'<polygon class="%s" points="%s" fill="%s" stroke="%s" stroke-width="%s"/>'
		% [kind, " ".join(points), fill, stroke, _n(width)]
	)


static func _text(at: Vector2, text: String, size: float) -> String:
	return (
		'<text x="%s" y="%s" font-size="%s" font-family="sans-serif" text-anchor="middle">%s</text>'
		% [_n(at.x), _n(at.y), _n(size), text.xml_escape()]
	)


## A scale bar along the bottom and an arrow to -Z in the top corner.
static func _svg_scale_and_arrow(view: Rect2, width: float) -> PackedStringArray:
	var out := PackedStringArray()
	var bar := scale_bar_metres(view.size.x)
	var left := Vector2(view.position.x + MARGIN * 0.5, view.end.y - MARGIN * 0.4)
	var tick := MARGIN * 0.15
	(
		out
		. append(
			(
				'<path class="scale" d="M %s %s L %s %s M %s %s L %s %s M %s %s L %s %s" stroke="%s" stroke-width="%s" fill="none"/>'
				% [
					_n(left.x),
					_n(left.y),
					_n(left.x + bar),
					_n(left.y),
					_n(left.x),
					_n(left.y - tick),
					_n(left.x),
					_n(left.y + tick),
					_n(left.x + bar),
					_n(left.y - tick),
					_n(left.x + bar),
					_n(left.y + tick),
					_hex("outline"),
					_n(width * 2.0)
				]
			)
		)
	)
	out.append(_text(left + Vector2(bar * 0.5, -tick * 1.5), "%s m" % _n(bar), MARGIN * 0.3))
	var tip := Vector2(view.end.x - MARGIN * 0.5, view.position.y + MARGIN * 0.2)
	var base := tip + Vector2(0.0, MARGIN * 0.6)
	(
		out
		. append(
			(
				'<path class="north" d="M %s %s L %s %s M %s %s L %s %s L %s %s" stroke="%s" stroke-width="%s" fill="none"/>'
				% [
					_n(base.x),
					_n(base.y),
					_n(tip.x),
					_n(tip.y),
					_n(tip.x - MARGIN * 0.15),
					_n(tip.y + MARGIN * 0.2),
					_n(tip.x),
					_n(tip.y),
					_n(tip.x + MARGIN * 0.15),
					_n(tip.y + MARGIN * 0.2),
					_hex("outline"),
					_n(width * 2.0)
				]
			)
		)
	)
	out.append(_text(base + Vector2(0.0, MARGIN * 0.3), "-Z", MARGIN * 0.25))
	return out


## A round length for the scale bar, about a fifth of `width`.
static func scale_bar_metres(width: float) -> float:
	var target := maxf(width / 5.0, 0.1)
	var step := pow(10.0, floorf(log(target) / log(10.0)))
	for factor in [5.0, 2.0, 1.0]:
		if step * factor <= target:
			return step * factor
	return step


## A coordinate to a millimetre, with no ".0" on a whole number and no "-0".
static func _n(value: float) -> String:
	if absf(value) < 0.0005:
		return "0"
	return String.num(value, 3).trim_suffix(".0")


static func _hex(kind: String) -> String:
	return "#" + (COLORS[kind] as Color).to_html(false)


# ---------------------------------------------------------------------------
# PNG
# ---------------------------------------------------------------------------


## The plan drawn into an image `size` pixels on its long side.
static func image(data: Dictionary, size: int = 1024) -> Image:
	var view: Rect2 = (data["bounds"] as Rect2).grow(MARGIN)
	var scale := float(maxi(size, 16)) / maxf(view.size.x, view.size.y)
	var width := maxi(1, ceili(view.size.x * scale))
	var height := maxi(1, ceili(view.size.y * scale))
	var picture := Image.create(width, height, false, Image.FORMAT_RGBA8)
	picture.fill(COLORS["background"])
	var to_pixels := func(point: Vector2) -> Vector2: return (point - view.position) * scale
	for outline in data["solids"]:
		var pixels := _pixels(outline, to_pixels)
		_fill(picture, pixels, COLORS["solid"], false)
		_outline(picture, pixels, COLORS["outline"])
	for outline in data["cuts"]:
		var pixels := _pixels(outline, to_pixels)
		_fill(picture, pixels, COLORS["cut"], true)
		_outline(picture, pixels, COLORS["cut"])
	for outline in data["brush_entities"]:
		_outline(picture, _pixels(outline, to_pixels), COLORS["brush_entity"])
	for box in data["cordons"]:
		var corners := PackedVector2Array(
			[
				box.position,
				Vector2(box.end.x, box.position.y),
				box.end,
				Vector2(box.position.x, box.end.y)
			]
		)
		_outline(picture, _pixels(corners, to_pixels), COLORS["cordon"], 6)
	for wire in data["wires"]:
		_line(picture, to_pixels.call(wire[0]), to_pixels.call(wire[1]), COLORS["wire"])
	for entity in data["entities"]:
		_dot(picture, to_pixels.call(entity["at"]), SYMBOL_PIXELS, COLORS[entity["kind"]])
	_png_scale_and_arrow(picture, view, to_pixels)
	return picture


## The SVG's scale bar and arrow to -Z, in the same places. The PNG has no text,
## so `hf_plan` gives the bar's length in metres beside it.
static func _png_scale_and_arrow(picture: Image, view: Rect2, to_pixels: Callable) -> void:
	var color: Color = COLORS["outline"]
	var bar := scale_bar_metres(view.size.x)
	var left := Vector2(view.position.x + MARGIN * 0.5, view.end.y - MARGIN * 0.4)
	var tick := Vector2(0.0, MARGIN * 0.15)
	var right := left + Vector2(bar, 0.0)
	var tip := Vector2(view.end.x - MARGIN * 0.5, view.position.y + MARGIN * 0.2)
	var base := tip + Vector2(0.0, MARGIN * 0.6)
	var wing := Vector2(MARGIN * 0.15, MARGIN * 0.2)
	var strokes := [
		[left, right],
		[left - tick, left + tick],
		[right - tick, right + tick],
		[base, tip],
		[tip, tip + Vector2(-wing.x, wing.y)],
		[tip, tip + wing],
	]
	for stroke in strokes:
		var from: Vector2 = to_pixels.call(stroke[0])
		var to: Vector2 = to_pixels.call(stroke[1])
		# Two pixels wide, so it reads at any size.
		_line(picture, from, to, color)
		_line(picture, from + Vector2.ONE, to + Vector2.ONE, color)


static func _pixels(outline: PackedVector2Array, to_pixels: Callable) -> PackedVector2Array:
	var out := PackedVector2Array()
	for corner in outline:
		out.append(to_pixels.call(corner))
	return out


## Fill a polygon a row at a time: each row's crossings with the edges, in
## pairs. With `hatched`, only the pixels on the diagonal stripes.
static func _fill(picture: Image, polygon: PackedVector2Array, color: Color, hatched: bool) -> void:
	var top := INF
	var bottom := -INF
	for corner in polygon:
		top = minf(top, corner.y)
		bottom = maxf(bottom, corner.y)
	for row in range(maxi(0, floori(top)), mini(picture.get_height(), ceili(bottom) + 1)):
		var y := float(row) + 0.5
		var crossings: Array[float] = []
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
				crossings.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
		crossings.sort()
		for pair in range(0, crossings.size() - 1, 2):
			var from := maxi(0, roundi(crossings[pair]))
			var to := mini(picture.get_width(), roundi(crossings[pair + 1]))
			if to <= from:
				continue
			if not hatched:
				picture.fill_rect(Rect2i(from, row, to - from, 1), color)
				continue
			for column in range(from, to):
				if (column + row) % HATCH_PERIOD < HATCH_WIDTH:
					picture.set_pixel(column, row, color)


static func _outline(
	picture: Image, polygon: PackedVector2Array, color: Color, dash: int = 0
) -> void:
	for i in polygon.size():
		_line(picture, polygon[i], polygon[(i + 1) % polygon.size()], color, dash)


## A line between two points, a pixel wide; with `dash`, drawn that many pixels
## on and that many off.
static func _line(picture: Image, from: Vector2, to: Vector2, color: Color, dash: int = 0) -> void:
	var steps := maxi(1, ceili(from.distance_to(to)))
	for i in steps + 1:
		if dash > 0 and floori(float(i) / float(dash)) % 2 == 1:
			continue
		var at := from.lerp(to, float(i) / float(steps))
		var x := floori(at.x)
		var y := floori(at.y)
		if x >= 0 and y >= 0 and x < picture.get_width() and y < picture.get_height():
			picture.set_pixel(x, y, color)


static func _dot(picture: Image, at: Vector2, radius: int, color: Color) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var x := floori(at.x) + dx
			var y := floori(at.y) + dy
			if x >= 0 and y >= 0 and x < picture.get_width() and y < picture.get_height():
				picture.set_pixel(x, y, color)
