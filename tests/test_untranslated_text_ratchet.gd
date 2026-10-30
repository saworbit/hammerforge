extends GutTest

## Text HammerForge puts together in code and shows the mapper goes through
## `HFTranslation.t()` or `tn()`, with named placeholders, or no catalog can
## translate it (#1702). About a thousand strings were written before that was
## possible, so this does not ask for all of them at once. It counts, per file,
## the formatted strings given straight to a label, a tooltip, a title, a menu
## item, a screen reader's name, drawn text or a toast, sent with the level's
## `user_message` signal, or made a refusal with `HFOpResult`, and fails when a file's
## count goes up. A message the Console's log or the bridge reads as well goes
## through `HFTranslation.message()`, which keeps it English for them. A file whose count goes down
## fails too, until its line in the baseline is lowered, so the count only ever
## moves one way.
##
## Formatted means a literal with `%` or `.format()` after it. A plain literal is
## found by `tools/gen_pot.gd` and translated by its control already. The bridge's
## replies stay English (`mcp/`), as the guide says.
##
## Run with `HF_RATCHET_WRITE=1` set to write the counts as they are.

const ROOT := "res://addons/hammerforge"
const BASELINE := "res://tests/fixtures/untranslated_interface_text.json"
## Folders whose words stay English in every language.
const ENGLISH_ONLY := ["res://addons/hammerforge/mcp"]

var _sink := RegEx.create_from_string(
	(
		"(?:\\.text|\\btooltip_text|\\bplaceholder_text|\\bdialog_text|(?:^\\s*|\\.)title"
		+ "|\\baccessibility_name|\\baccessibility_description)"
		+ "\\s*=(?!=)(.*)$|(?:\\b(?:show_toast|_set_status|set_status|_toast|_say)\\("
		+ '|\\bemit_signal\\(\\s*"user_message"\\s*,|\\buser_message\\.emit\\('
		+ "|\\bHFOpResult\\.(?:fail|success)\\(|\\b_op_fail\\("
		+ "|\\b(?:add_item|add_check_item|add_radio_check_item|add_icon_item|add_icon_check_item"
		+ "|add_submenu_item|set_item_text|set_item_tooltip|set_tab_title|set_tab_tooltip"
		+ "|set_text|set_tooltip_text|make_button|make_check|make_label_row"
		+ "|draw_string|draw_multiline_string)\\()(.*)$"
	)
)
var _formatted := RegEx.create_from_string('"(?:[^"\\\\]|\\\\.)*"\\s*(?:%|\\.format\\()')
var _literal := RegEx.create_from_string('"(?:[^"\\\\]|\\\\.)*"')
## `HFTranslation.t()` and `tn()`, under either of the names the addon preloads
## it by, or Godot's own `tr()`, `tr_n()` and `atr()`. Whole names, so `str()`
## is not taken for `tr()`.
var _translated := RegEx.create_from_string("HFTranslation|(?<![A-Za-z_0-9])a?tr(?:_n)?\\(")


func test_no_file_gains_text_that_skips_translation():
	var counts := {}
	var found := {}
	var scanned := _scan(ROOT, counts, found)
	assert_gt(scanned, 0, "the scan reached the addon")
	if OS.get_environment("HF_RATCHET_WRITE") == "1":
		var file := FileAccess.open(BASELINE, FileAccess.WRITE)
		file.store_string(JSON.stringify(_sorted(counts), "\t") + "\n")
		file.close()
		pass_test("wrote %s" % BASELINE)
		return
	var baseline := _baseline()
	var problems: Array = []
	var paths: Array = counts.keys()
	for path in baseline:
		if not paths.has(path):
			paths.append(path)
	paths.sort()
	for path in paths:
		var now := int(counts.get(path, 0))
		var was := int(baseline.get(path, 0))
		if now > was:
			(
				problems
				. append(
					(
						"%s has %d formatted strings shown without HFTranslation.t(), %d more than before, among: %s"
						% [path, now, now - was, "; ".join(found[path].slice(0, 8))]
					)
				)
			)
		elif now < was:
			problems.append(
				(
					"%s is down to %d: lower its line in %s from %d to %d"
					% [path, now, BASELINE, was, now]
				)
			)
	assert_eq(problems, [], "see docs/translating.md, Adding a label")


func test_a_missing_directory_does_not_count_as_scanned():
	var missing := "user://ratchet_missing_" + str(get_instance_id())
	assert_eq(_scan(missing, {}, {}), 0)


func test_the_detector_still_finds_untranslated_formatted_text():
	assert_eq(_hits('label.text = "Name %s" % value').size(), 1)
	assert_eq(_hits('label.text = "Name %s" % str(value)').size(), 1, "str() is not tr()")
	assert_eq(_hits('label.text = tr("Name %s") % value'), [])
	assert_eq(_hits('label.text = HFTranslation.t("Name {name}").format({"name": value})'), [])
	assert_eq(_hits('root.user_message.emit("Saved %s" % path, 0)').size(), 1, "a level message")
	assert_eq(_hits('root.emit_signal("user_message", "Saved %s" % path, 0)').size(), 1)
	assert_eq(_hits('root.user_message.emit(HFTranslation.message("Saved {file}", f), 0)'), [])
	assert_eq(_hits('return HFOpResult.fail("Arch: %s" % x, "Use %d" % n)').size(), 1, "a refusal")
	assert_eq(_hits('menu.add_item("Place %s Here" % name, 3)').size(), 1, "a menu item")
	assert_eq(_hits('lamp.accessibility_name = "Status: %s" % word').size(), 1, "a screen reader's")


func _baseline() -> Dictionary:
	if not FileAccess.file_exists(BASELINE):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
	return parsed if parsed is Dictionary else {}


func _scan(dir: String, counts: Dictionary, found: Dictionary) -> int:
	if ENGLISH_ONLY.has(dir):
		return 0
	var access := DirAccess.open(dir)
	if access == null:
		return 0
	var scanned := 0
	for sub in access.get_directories():
		scanned += _scan(dir.path_join(sub), counts, found)
	for file_name in access.get_files():
		if file_name.get_extension() != "gd":
			continue
		scanned += 1
		var path := dir.path_join(file_name)
		var hits := _hits(FileAccess.get_file_as_string(path))
		if not hits.is_empty():
			counts[path] = hits.size()
			found[path] = hits
	return scanned


## The statements of `source` that hand a sink a formatted literal not put
## through a translation call. A statement gdformat wrapped over several lines is
## read whole.
func _hits(source: String) -> Array:
	var out: Array = []
	var statement := ""
	var depth := 0
	for line in source.split("\n"):
		var stripped := line.strip_edges()
		if statement == "" and (stripped == "" or stripped.begins_with("#")):
			continue
		statement += " " + stripped
		var bare := _literal.sub(stripped, '""', true)
		var hash_at := bare.find("#")
		if hash_at >= 0:
			bare = bare.left(hash_at)
		for ch in bare:
			if ch in ["(", "[", "{"]:
				depth += 1
			elif ch in [")", "]", "}"]:
				depth -= 1
		if depth > 0:
			continue
		depth = 0
		var sunk := _sink.search(statement)
		if sunk:
			var value := sunk.get_string(1) + sunk.get_string(2)
			if _translated.search(value) == null and _formatted.search(value):
				out.append(statement.strip_edges().left(90))
		statement = ""
	return out


static func _sorted(counts: Dictionary) -> Dictionary:
	var out := {}
	var keys: Array = counts.keys()
	keys.sort()
	for key in keys:
		out[key] = counts[key]
	return out
