@tool
class_name HFHash
extends RefCounted


static func floor_id(
	layer_id: StringName, chunk: Vector2i, min_cell: Vector2i, size: Vector2i
) -> StringName:
	return StringName(
		(
			"hf:floor:v1:%s:%s,%s:%s,%s:%sx%s"
			% [layer_id, chunk.x, chunk.y, min_cell.x, min_cell.y, size.x, size.y]
		)
	)


static func wall_id(
	layer_id: StringName, chunk: Vector2i, a: Vector2i, b: Vector2i, outward: Vector2i
) -> StringName:
	return StringName(
		(
			"hf:wall:v1:%s:%s,%s:%s,%s->%s,%s:%s,%s"
			% [layer_id, chunk.x, chunk.y, a.x, a.y, b.x, b.y, outward.x, outward.y]
		)
	)


static func short_wall_id(layer_id: StringName, chunk: Vector2i, sig: String) -> StringName:
	return StringName("hf:wall:v1:%s:%s,%s:%s" % [layer_id, chunk.x, chunk.y, hash32(sig)])


static func chunk_tag_from_id(gid: StringName) -> String:
	var parts = str(gid).split(":")
	if parts.size() < 5:
		return ""
	return str(parts[4])


static func hash32(text: String) -> String:
	var h = text.hash()
	var u = int(h) & 0xffffffff
	return "%08x" % u
