@tool
class_name HFTextureFolder
extends RefCounted
## Add Texture Folder (#1884): every image in a folder as a palette material.
## Files that share a base name and end in a map's name are one material, so
## `brick_albedo.png`, `brick_normal.png` and `brick_roughness.png` make one
## brick with all three maps set, and `tile.png` makes a tile with its albedo.
##
## Each material is written as a `.tres`, beside its textures or in a folder of
## its own, so it keeps a path through a save and the material library as the
## prototype materials do. One already written is used again, never rebuilt.

## The images it reads, by extension.
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "tga", "bmp", "exr", "hdr", "svg"]

## The map each suffix names, lower case and with its own separators taken out,
## so `base_color` and `normal_gl` match as `basecolor` and `normalgl`. A file
## with none of these at the end is an albedo, named for the whole file.
const SUFFIXES := {
	"albedo": "albedo",
	"basecolor": "albedo",
	"diffuse": "albedo",
	"diff": "albedo",
	"color": "albedo",
	"col": "albedo",
	"normal": "normal",
	"normalgl": "normal",
	"normaldx": "normal",
	"norgl": "normal",
	"nordx": "normal",
	"nrm": "normal",
	"nor": "normal",
	"roughness": "roughness",
	"rough": "roughness",
	"metallic": "metallic",
	"metalness": "metallic",
	"metal": "metallic",
	"ao": "ao",
	"occlusion": "ao",
	"ambientocclusion": "ao",
}

## Suffixes of maps a material made here has no use for: a height map, a packed
## occlusion, roughness and metal map, and the like. Packs ship them with the rest
## of a set, so they are read as part of it and named in the report, rather than
## each made an albedo of its own (#1960).
const UNUSED_SUFFIXES := [
	"arm",
	"bump",
	"cavity",
	"disp",
	"displacement",
	"gloss",
	"glossiness",
	"height",
	"opacity",
	"spec",
	"specular",
]

## The map `split_name()` names for a file of one of `UNUSED_SUFFIXES`.
const UNUSED := "unused"

## A DirectX normal map, which Godot reads the wrong way up until its Normal Map
## Invert Y import setting is on.
const DIRECTX_SUFFIXES := ["normaldx", "nordx"]

const SEPARATORS := ["_", "-", " "]

## Where every material is written when it is not to go beside its textures, or
## "" for beside them. The test run sets it to a folder of its own
## (`tests/support/gut_pre_run.gd`), so a run never writes into the project.
static var write_dir := ""


## `file_name` as `[base, map, directx]`: the name its set goes by, the map it
## is, and whether it is a DirectX normal map. Case does not matter, and `_`, `-`
## or a space can separate the name from the suffix. A resolution or a format
## after the suffix, as in `brick_diff_2k.png`, is passed over to find it and
## kept in the name, so a 2k set and a 4k set of one texture are two sets (#1960).
static func split_name(file_name: String) -> Array:
	var stem := file_name.get_basename()
	var lower := stem.to_lower()
	# Where each word starts, so the last one or two can be tried as a suffix.
	var starts: Array = [0]
	for i in lower.length():
		if SEPARATORS.has(lower[i]) and i + 1 < lower.length():
			starts.append(i + 1)
	var end := lower.length()
	var last := starts.size()
	while last > 1 and _is_size_or_format(lower.substr(starts[last - 1], end - starts[last - 1])):
		last -= 1
		end = starts[last] - 1
	for words in [2, 1]:
		if last <= words:
			continue
		var at: int = starts[last - words]
		var suffix := lower.substr(at, end - at)
		for separator in SEPARATORS:
			suffix = suffix.replace(separator, "")
		var map_name := _map_of(suffix)
		if map_name != "":
			var base := (stem.substr(0, at - 1) + stem.substr(end)).strip_edges()
			if base != "":
				return [base, map_name, DIRECTX_SUFFIXES.has(suffix)]
	return [stem, "albedo", false]


## The map `suffix` names, `UNUSED` for one a material has no use for, or "".
static func _map_of(suffix: String) -> String:
	if SUFFIXES.has(suffix):
		return SUFFIXES[suffix]
	return UNUSED if UNUSED_SUFFIXES.has(suffix) else ""


## Whether `word` is a resolution, `1k` to `16k`, or an image format.
static func _is_size_or_format(word: String) -> bool:
	if IMAGE_EXTENSIONS.has(word):
		return true
	return word.length() > 1 and word.ends_with("k") and word.left(-1).is_valid_int()


## The images among `file_names`, sorted into sets: `{"sets": [{"name", "albedo",
## "normal", ...}], "unplaced": [file], "unused": [file], "directx": [file]}`. A
## set takes its name from the first file of it, and is matched to the others
## without regard to case. A second file for a map a set has already, or a set
## with no albedo, is left unplaced, to be named in the report. A map a set has
## no use for is named as unused.
##
## A file whose name ends in a map word is an albedo when it is a plain texture
## named so: when its whole name begins another set, as `sheet_metal.png` does
## beside `sheet_metal_normal.png`, or when it is alone, as `sheet_metal.png` is
## in a folder of its own. A normal map alone is no picture to wear, and stays
## unplaced (#1960).
static func sets_of(file_names: Array) -> Dictionary:
	var names: Array = []
	for file_name in file_names:
		if IMAGE_EXTENSIONS.has(str(file_name).get_extension().to_lower()):
			names.append(str(file_name))
	names.sort()
	var parts_of: Dictionary = {}
	var bases: Dictionary = {}
	for file_name in names:
		parts_of[file_name] = split_name(file_name)
		bases[str(parts_of[file_name][0]).to_lower()] = true
	for file_name in names:
		var stem: String = file_name.get_basename()
		if parts_of[file_name][1] != "albedo" and bases.has(stem.to_lower()):
			parts_of[file_name] = [stem, "albedo", false]
	var by_key: Dictionary = {}
	var order: Array = []
	var files_of: Dictionary = {}
	var unused_of: Dictionary = {}
	var unplaced: Array = []
	var directx: Array = []
	for file_name in names:
		var parts: Array = parts_of[file_name]
		var key := str(parts[0]).to_lower()
		if not by_key.has(key):
			by_key[key] = {"name": parts[0]}
			order.append(key)
			files_of[key] = []
			unused_of[key] = []
		files_of[key].append(file_name)
		var found: Dictionary = by_key[key]
		if parts[1] == UNUSED:
			unused_of[key].append(file_name)
			continue
		if found.has(parts[1]):
			# A pack that ships a DirectX and an OpenGL normal map is read with the
			# OpenGL one, which Godot reads the right way up.
			if parts[1] == "normal" and parts[2] != directx.has(found["normal"]):
				var directx_file: String = file_name if parts[2] else found["normal"]
				unused_of[key].append(directx_file)
				directx.erase(directx_file)
				if not parts[2]:
					found["normal"] = file_name
			else:
				unplaced.append(file_name)
			continue
		found[parts[1]] = file_name
		if parts[2]:
			directx.append(file_name)
	var sets: Array = []
	var unused: Array = []
	for key in order:
		var found: Dictionary = by_key[key]
		var files: Array = files_of[key]
		if not found.has("albedo") and files.size() == 1 and not found.has("normal"):
			sets.append({"name": str(files[0]).get_basename(), "albedo": files[0]})
			continue
		if not found.has("albedo"):
			for file_name in files:
				if not unplaced.has(file_name):
					unplaced.append(file_name)
			continue
		sets.append(found)
		unused.append_array(unused_of[key])
	unplaced.sort()
	unused.sort()
	return {"sets": sets, "unplaced": unplaced, "unused": unused, "directx": directx}


## Every set in `folder` as a material: a `.tres` written for each, in `out_dir`
## or beside its textures, or the one there already. Returns `{"materials",
## "made", "reused", "unplaced", "unused", "directx", "error"}`. A texture that
## does not load leaves its set out, unplaced, and the rest go on.
static func build(folder: String, out_dir: String = "") -> Dictionary:
	var out := _result()
	if not DirAccess.dir_exists_absolute(folder):
		out["error"] = "no folder at %s" % folder
		return out
	var found := sets_of(Array(DirAccess.get_files_at(folder)))
	out["unplaced"] = found["unplaced"]
	out["unused"] = found["unused"]
	out["directx"] = found["directx"]
	for set_of in found["sets"]:
		_take_set(folder, set_of, _target(folder, out_dir), out)
	return out


## The material for the set the image at `image_path` is in, made or reused as
## Add Texture Folder makes it, for a drop of the image on a face to wear. What
## `build()` returns, for that one set; an image in no set with an albedo makes
## nothing, and `error` says so.
static func build_for_image(image_path: String) -> Dictionary:
	var out := _result()
	var folder := image_path.get_base_dir()
	var file_name := image_path.get_file()
	var found := sets_of(Array(DirAccess.get_files_at(folder)))
	for set_of in found["sets"]:
		if not (set_of as Dictionary).values().has(file_name):
			continue
		for directx in found["directx"]:
			if (set_of as Dictionary).values().has(directx):
				out["directx"].append(directx)
		_take_set(folder, set_of, _target(folder, ""), out)
		return out
	if (found["unused"] as Array).has(file_name):
		out["error"] = "%s is a map a material made here does not use" % file_name
	else:
		out["error"] = "%s is in no set with an albedo" % file_name
	return out


static func _result() -> Dictionary:
	return {
		"materials": [],
		"made": 0,
		"reused": 0,
		"unplaced": [],
		"unused": [],
		"directx": [],
		"error": "",
	}


static func _target(folder: String, out_dir: String) -> String:
	var target := out_dir if out_dir != "" else (write_dir if write_dir != "" else folder)
	if not DirAccess.dir_exists_absolute(target):
		DirAccess.make_dir_recursive_absolute(target)
	return target


## Make `set_of`'s material in `target`, or take the one written there already,
## and note it in `out`.
static func _take_set(folder: String, set_of: Dictionary, target: String, out: Dictionary) -> void:
	var path := target.path_join("%s.tres" % set_of["name"])
	if ResourceLoader.exists(path):
		var kept = ResourceLoader.load(path)
		if kept is Material:
			out["materials"].append(kept)
			out["reused"] += 1
			return
	var material := _material_of(folder, set_of)
	if material == null:
		for map_name in set_of:
			if map_name != "name":
				out["unplaced"].append(set_of[map_name])
		return
	material.take_over_path(path)
	var err := ResourceSaver.save(material, path)
	if err != OK:
		out["error"] = "could not write %s (error %d)" % [path, err]
		return
	out["materials"].append(material)
	out["made"] += 1


## A StandardMaterial3D with each map of `set_of` set, or null when one of its
## textures does not load.
static func _material_of(folder: String, set_of: Dictionary) -> StandardMaterial3D:
	var textures: Dictionary = {}
	for map_name in set_of:
		if map_name == "name":
			continue
		var texture = ResourceLoader.load(folder.path_join(set_of[map_name]))
		if not (texture is Texture2D):
			return null
		textures[map_name] = texture
	var material := StandardMaterial3D.new()
	material.resource_name = str(set_of["name"])
	material.albedo_texture = textures["albedo"]
	if textures.has("normal"):
		material.normal_enabled = true
		material.normal_texture = textures["normal"]
	if textures.has("roughness"):
		material.roughness_texture = textures["roughness"]
	if textures.has("metallic"):
		# A metallic map scales the metallic value, so it reads as drawn at 1.
		material.metallic = 1.0
		material.metallic_texture = textures["metallic"]
	if textures.has("ao"):
		material.ao_enabled = true
		material.ao_texture = textures["ao"]
	return material


## What a run made of a folder, in a sentence or two for the toast.
static func report(built: Dictionary) -> String:
	if str(built.get("error", "")) != "" and (built.get("materials", []) as Array).is_empty():
		return "Add Texture Folder: %s" % built["error"]
	var made := int(built.get("made", 0))
	var reused := int(built.get("reused", 0))
	var text := (
		"Add Texture Folder: %d material%s made, %d reused"
		% [made, "" if made == 1 else "s", reused]
	)
	var unplaced: Array = built.get("unplaced", [])
	if not unplaced.is_empty():
		text += ". Not placed in a set: %s" % ", ".join(unplaced)
	var unused: Array = built.get("unused", [])
	if not unused.is_empty():
		text += ". Maps not used: %s" % ", ".join(unused)
	var directx: Array = built.get("directx", [])
	if not directx.is_empty():
		text += (
			". DirectX normal map%s, turn on Normal Map Invert Y in the Import dock: %s"
			% ["" if directx.size() == 1 else "s", ", ".join(directx)]
		)
	if str(built.get("error", "")) != "":
		text += ". %s" % built["error"]
	return text
