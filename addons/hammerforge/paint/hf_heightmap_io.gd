@tool
class_name HFHeightmapIO
extends RefCounted


static func load_from_file(path: String) -> Image:
	var img := Image.load_from_file(path)
	if img == null:
		push_error("HFHeightmapIO: Failed to load '%s'" % path)
		return null
	img.convert(Image.FORMAT_RF)
	return img


## A noise image that tiles. A paint layer does not use one: Generate Noise
## gives the layer the noise itself (`HFPaintLayer.set_height_noise()`).
static func generate_noise(width: int, height: int, settings: Dictionary = {}) -> Image:
	var noise := make_noise(noise_settings(settings))
	var img := noise.get_seamless_image(width, height, false, false)
	img.convert(Image.FORMAT_RF)
	return img


## `settings` with each of type, frequency, octaves and seed filled in, and a
## value that is not one of its kind, as a damaged file can hold, read as the
## default.
static func noise_settings(settings: Dictionary) -> Dictionary:
	var frequency := _number(settings.get("frequency"), 0.01)
	return {
		"type": clampi(int(_number(settings.get("type"), FastNoiseLite.TYPE_SIMPLEX_SMOOTH)), 0, 5),
		"frequency": frequency if frequency > 0.0 else 0.01,
		"octaves": clampi(int(_number(settings.get("octaves"), 4)), 1, 10),
		"seed": int(_number(settings.get("seed"), 0)),
	}


## The noise `settings` describe, from `noise_settings()`.
static func make_noise(settings: Dictionary) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = int(settings.get("type", 1)) as FastNoiseLite.NoiseType
	noise.frequency = float(settings.get("frequency", 0.01))
	noise.fractal_octaves = int(settings.get("octaves", 4))
	noise.seed = int(settings.get("seed", 0))
	return noise


static func _number(value: Variant, fallback: float) -> float:
	if (value is int or value is float) and is_finite(float(value)):
		return float(value)
	return fallback


## Heightmaps are FORMAT_RF - one 32 bit float per sample - so they are stored
## as the raw float buffer, zstd compressed, behind a small header. PNG has no
## float channel: it would round every sample to 8 bits and clamp it to 0..1,
## and because the same encoder backs capture_state() that loss applied to undo
## as well as to the saved file.
const RAW_MAGIC := 0x4D484648  # "HFHM"
const RAW_VERSION := 1
const RAW_HEADER_SIZE := 20


static func encode_to_base64(img: Image) -> String:
	if img == null or img.is_empty():
		return ""
	var src := img
	if src.get_format() != Image.FORMAT_RF:
		src = Image.new()
		src.copy_from(img)
		src.convert(Image.FORMAT_RF)
	var pixels := src.get_data()
	var packed := pixels.compress(FileAccess.COMPRESSION_ZSTD)
	var buf := PackedByteArray()
	buf.resize(RAW_HEADER_SIZE)
	buf.encode_u32(0, RAW_MAGIC)
	buf.encode_u32(4, RAW_VERSION)
	buf.encode_u32(8, src.get_width())
	buf.encode_u32(12, src.get_height())
	buf.encode_u32(16, pixels.size())
	buf.append_array(packed)
	return Marshalls.raw_to_base64(buf)


static func decode_from_base64(data: String) -> Image:
	if data == "":
		return null
	var raw := Marshalls.base64_to_raw(data)
	if raw.size() >= RAW_HEADER_SIZE and raw.decode_u32(0) == RAW_MAGIC:
		return _decode_raw(raw)
	# Levels saved before the float format stored an 8 bit PNG.
	var img := Image.new()
	if img.load_png_from_buffer(raw) != OK:
		push_error("HFHeightmapIO: Failed to decode heightmap from base64")
		return null
	img.convert(Image.FORMAT_RF)
	return img


static func _decode_raw(raw: PackedByteArray) -> Image:
	var version := int(raw.decode_u32(4))
	if version != RAW_VERSION:
		push_error(
			(
				(
					"HFHeightmapIO: Heightmap format version %d was written by a newer "
					+ "HammerForge and cannot be read here."
				)
				% version
			)
		)
		return null
	var w := int(raw.decode_u32(8))
	var h := int(raw.decode_u32(12))
	var expected := int(raw.decode_u32(16))
	if w <= 0 or h <= 0 or expected != w * h * 4:
		push_error("HFHeightmapIO: Heightmap header describes %dx%d in %d bytes" % [w, h, expected])
		return null
	var pixels := raw.slice(RAW_HEADER_SIZE).decompress(expected, FileAccess.COMPRESSION_ZSTD)
	if pixels.size() != expected:
		push_error(
			(
				"HFHeightmapIO: Heightmap payload unpacked to %d bytes, expected %d"
				% [pixels.size(), expected]
			)
		)
		return null
	return Image.create_from_data(w, h, false, Image.FORMAT_RF, pixels)
