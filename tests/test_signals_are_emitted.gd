extends GutTest

## Every signal the addon declares has to be emitted somewhere in it.
##
## A signal that is never emitted is wiring that reads as load-bearing and is
## not. Four of them accumulated by September 2026, two with connect and
## disconnect pairs in `plugin.gd` and a real handler on the other end, for a
## command nothing in the viewport could ask for. Nothing was broken by any of
## them; the cost was in reading the code.
##
## A whole-tree grep, the way `test_suite_integrity.gd` checks that every test
## script loads.

const ADDON_DIR := "res://addons/hammerforge/"

## Signals declared for something outside the addon to emit. Each needs a reason.
const EMITTED_ELSEWHERE := {}

## The characters a GDScript identifier is made of, for the word boundary below.
const IDENTIFIER_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"


func _gd_files(dir_path: String, out: PackedStringArray) -> PackedStringArray:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			out.append(dir_path + file_name)
	for sub in dir.get_directories():
		_gd_files(dir_path + sub + "/", out)
	return out


func _addon_sources() -> Dictionary:
	var sources: Dictionary = {}
	for path in _gd_files(ADDON_DIR, PackedStringArray()):
		sources[path] = FileAccess.get_file_as_string(path)
	return sources


## The signal names one file declares, in declaration order.
func _declared_signals(source: String) -> PackedStringArray:
	var out := PackedStringArray()
	for raw_line in source.split("\n"):
		var line := raw_line.strip_edges()
		if not line.begins_with("signal "):
			continue
		var rest := line.substr(7).strip_edges()
		var end := rest.length()
		for i in rest.length():
			var ch := rest[i]
			if not (ch.is_valid_identifier() or ch == "_" or ch.to_lower() != ch.to_upper()):
				end = i
				break
			if ch == "(" or ch == " ":
				end = i
				break
		out.append(rest.substr(0, end).strip_edges())
	return out


## The shapes an emit takes.
##
## `name.emit(` is the direct one. The rest are the name as a string literal on a
## line that emits: `emit_signal("name")`, and the forwarding helpers the
## subsystems use, like `_emit_entity_signal("entity_added", entity)` and
## `_emit_or_batch("face_selection_changed", [])`. Requiring `emit` on the line
## keeps a `connect("name", ...)` from counting as one.
func _is_emitted(signal_name: String, sources: Dictionary) -> bool:
	var dot_form := "%s.emit(" % signal_name
	var double_quoted := '"%s"' % signal_name
	var single_quoted := "'%s'" % signal_name
	for path in sources:
		var text: String = sources[path]
		if _contains_at_word_start(text, dot_form):
			return true
		if not (text.contains(double_quoted) or text.contains(single_quoted)):
			continue
		for line in text.split("\n"):
			if not line.contains("emit"):
				continue
			if line.contains(double_quoted) or line.contains(single_quoted):
				return true
	return false


func test_the_scan_finds_the_addon():
	var sources := _addon_sources()
	assert_gt(sources.size(), 100, "the file walk found nothing, which cannot be right")


func test_the_scan_finds_signals_to_check():
	var count := 0
	for path in _addon_sources().values():
		count += _declared_signals(path).size()
	assert_gt(count, 20, "no signals were parsed, so this check would pass on anything")


func test_every_declared_signal_is_emitted_somewhere_in_the_addon():
	var sources := _addon_sources()
	var never_emitted: Array = []
	for path in sources:
		for signal_name in _declared_signals(sources[path]):
			if signal_name == "" or EMITTED_ELSEWHERE.has(signal_name):
				continue
			if not _is_emitted(signal_name, sources):
				never_emitted.append("%s: %s" % [str(path).replace(ADDON_DIR, ""), signal_name])
	assert_eq(
		never_emitted,
		[],
		(
			"These signals are declared and never emitted. Emit them, or delete them "
			+ "along with whatever connects to them: %s" % str(never_emitted)
		)
	)


## `text.contains()` with a left word boundary.
##
## Without it `layer_changed.emit(` matches inside `paint_layer_changed.emit(`,
## and a signal goes uncounted because a differently named one shares its tail.
func _contains_at_word_start(text: String, needle: String) -> bool:
	var from := 0
	while true:
		var at := text.find(needle, from)
		if at < 0:
			return false
		if at == 0 or not IDENTIFIER_CHARS.contains(text[at - 1]):
			return true
		from = at + 1
	return false
