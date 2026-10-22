extends "res://tests/mcp/mcp_dispatcher_case.gd"
## The building guide tells an agent what each read costs, measured on the
## reference map (#1650). These measure the same replies again and hold the
## guide's table to them, so it stays measured rather than guessed.

const REFERENCE := "res://addons/hammerforge/data/reference_map.hflevel"
const COSTS := "res://hammerforge_mcp/skills/hammerforge-building/reference/costs.md"
## How far a reply may drift from the table before the table is wrong.
const DRIFT := 0.25

## The reads the table lists, by the label its first column gives each.
const READS := {
	"hf_get_status": ["hf_get_status", {}],
	"hf_get_brushes": ["hf_get_brushes", {}],
	"hf_get_brushes, include_faces false": ["hf_get_brushes", {"include_faces": false}],
	"hf_get_entities": ["hf_get_entities", {}],
	"hf_list_commands": ["hf_list_commands", {}],
	"hf_validate": ["hf_validate", {}],
}


## Kilobytes by label, read from the table's rows: `| label | KB | ... |`.
static func _table() -> Dictionary:
	var out := {}
	for line in FileAccess.get_file_as_string(COSTS).split("\n"):
		var cells := line.split("|", false)
		if cells.size() < 2:
			continue
		var label := cells[0].strip_edges().trim_prefix("`").trim_suffix("`")
		var kb := cells[1].strip_edges()
		if READS.has(label) and kb.is_valid_float():
			out[label] = float(kb)
	return out


func test_the_guide_s_reply_sizes_are_what_the_reference_map_gives():
	var level := make_level()
	assert_true(level.load_hflevel(REFERENCE), "fixture: the reference map loads")
	var table := _table()
	assert_eq(table.size(), READS.size(), "the table lists every read: %s" % str(table))
	for label in READS:
		var r := await call_tool(READS[label][0], READS[label][1])
		assert_true(r.get("ok", false), "%s answers: %s" % [label, str(r).left(200)])
		var kb := JSON.stringify(r).to_utf8_buffer().size() / 1024.0
		gut.p("%s: %.1f KB" % [label, kb])
		if table.has(label):
			var stated: float = table[label]
			assert_almost_eq(
				kb, stated, maxf(stated * DRIFT, 0.5), "%s is about %.1f KB" % [label, stated]
			)
