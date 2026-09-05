@tool
class_name HFStatusBoard
extends RefCounted
## The red / amber / green board behind the HammerForge Console's Status tab.
##
## Two halves, deliberately separated:
##
##   collect_context()  reads the live editor — LevelRoot, log — and is the only
##                      part that touches engine state.
##   evaluate()         turns that snapshot into check rows and is pure, so
##                      every threshold in here is testable without an editor.
##
## A check never says only "warning". It says what was measured, what the
## threshold is, and the one button that resolves it — a light with no next
## action is just an alarm.

enum Severity {
	OK,  ## Green. Nothing to do.
	WARN,  ## Amber. Works, but will bite later or is a known compromise.
	PROBLEM,  ## Red. Something is broken or will not do what you expect.
	UNKNOWN,  ## Grey. Not measurable yet — usually because nothing is loaded.
}

## Above this many brushes + entities the editor's per-frame reconcile starts to
## show; above PROBLEM it is visible on every drag. Mirrors LevelRoot's own
## get_level_health() thresholds so the dock and the console cannot disagree.
const GEOMETRY_WARN := 50
const GEOMETRY_PROBLEM := 100

## A handful of validation issues is ordinary mid-edit. A pile of them means the
## next bake will not produce what the viewport is showing.
const VALIDATION_PROBLEM := 6

const SEVERITY_LABELS := {
	Severity.OK: "OK",
	Severity.WARN: "Attention",
	Severity.PROBLEM: "Problem",
	Severity.UNKNOWN: "Not measured",
}


static func severity_label(severity: int) -> String:
	return SEVERITY_LABELS.get(severity, "Not measured")


# ---------------------------------------------------------------------------
# Context
# ---------------------------------------------------------------------------


## Snapshot the editor into a plain dictionary. Every read is guarded: the
## console is alive before a scene is open, while a scene is being swapped, and
## after a LevelRoot has been freed out from under it.
##
## `cached` carries results the board cannot afford to recompute on a timer —
## validation walks every brush — so the caller owns when those refresh.
##
## `deep` gates the two reads that are O(brushes x faces): the vertex estimate
## and the recommended chunk size, which both walk the whole level. The console
## polls shallow once a second and goes deep only when the reader asks or the
## level changes, so an idle editor with a large level costs nothing.
static func collect_context(
	level_root, console_log, cached: Dictionary = {}, deep: bool = false
) -> Dictionary:
	var ctx := _empty_context()
	if console_log and console_log.has_method("counts"):
		var counts: Dictionary = console_log.counts()
		ctx["log_warn"] = int(counts.get("warn", 0))
		ctx["log_error"] = int(counts.get("error", 0))
	for key in cached.keys():
		ctx[key] = cached[key]
	if level_root == null or not is_instance_valid(level_root):
		return ctx

	ctx["has_root"] = true
	ctx["root_name"] = str(level_root.name)
	if level_root.has_method("get_live_brush_count"):
		ctx["brush_count"] = int(level_root.get_live_brush_count())
	if level_root.has_method("get_entity_count"):
		ctx["entity_count"] = int(level_root.get_entity_count())
	if deep and level_root.has_method("get_total_vertex_estimate"):
		ctx["vertex_estimate"] = int(level_root.get_total_vertex_estimate())
	if level_root.has_method("get_paint_memory_bytes"):
		ctx["paint_memory_bytes"] = int(level_root.get_paint_memory_bytes())
	if level_root.has_method("get_bake_chunk_count"):
		ctx["bake_chunk_count"] = int(level_root.get_bake_chunk_count())
	if level_root.has_method("get_last_bake_duration_ms"):
		ctx["last_bake_ms"] = int(level_root.get_last_bake_duration_ms())
	if deep and level_root.has_method("get_recommended_chunk_size"):
		ctx["recommended_chunk_size"] = float(level_root.get_recommended_chunk_size())
	if level_root.has_method("get_level_health"):
		var health: Dictionary = level_root.get_level_health()
		ctx["health_label"] = str(health.get("label", ""))
		ctx["health_severity"] = int(health.get("severity", Severity.UNKNOWN))

	var baked = level_root.get("baked_container")
	if baked and is_instance_valid(baked):
		ctx["baked_count"] = baked.get_child_count()
	var dirty = level_root.get("_dirty_brush_ids")
	if dirty is Dictionary:
		ctx["dirty_brush_count"] = dirty.size()

	var material_manager = level_root.get("material_manager")
	if material_manager and is_instance_valid(material_manager):
		var materials = material_manager.get("materials")
		if materials is Array:
			var loaded := 0
			for mat in materials:
				if mat != null:
					loaded += 1
			ctx["material_count"] = loaded

	var spawn_system = level_root.get("spawn_system")
	if spawn_system and spawn_system.has_method("get_all_spawns"):
		ctx["spawn_count"] = spawn_system.get_all_spawns().size()

	ctx["chunk_size"] = _get_float(level_root, "bake_chunk_size", 0.0)
	ctx["bake_use_face_materials"] = _get_bool(level_root, "bake_use_face_materials", false)
	ctx["auto_spawn_player"] = _get_bool(level_root, "auto_spawn_player", false)
	ctx["autosave_enabled"] = _get_bool(level_root, "hflevel_autosave_enabled", false)
	ctx["autosave_minutes"] = int(_get_float(level_root, "hflevel_autosave_minutes", 0.0))
	var autosave_raw = level_root.get("hflevel_autosave_path")
	var autosave_path := "" if autosave_raw == null else str(autosave_raw)
	ctx["autosave_path"] = autosave_path
	if autosave_path != "" and FileAccess.file_exists(autosave_path):
		ctx["autosave_exists"] = true
		var modified := int(FileAccess.get_modified_time(autosave_path))
		if modified > 0:
			ctx["autosave_age_sec"] = maxi(0, int(Time.get_unix_time_from_system()) - modified)
	return ctx


static func _empty_context() -> Dictionary:
	return {
		"has_root": false,
		"root_name": "",
		"brush_count": 0,
		"entity_count": 0,
		"vertex_estimate": 0,
		"paint_memory_bytes": 0,
		"health_label": "",
		"health_severity": Severity.UNKNOWN,
		"baked_count": 0,
		"dirty_brush_count": 0,
		"last_bake_ms": 0,
		"bake_chunk_count": 0,
		"recommended_chunk_size": 0.0,
		"chunk_size": 0.0,
		"material_count": 0,
		"bake_use_face_materials": false,
		"spawn_count": 0,
		"auto_spawn_player": false,
		"autosave_enabled": false,
		"autosave_minutes": 0,
		"autosave_path": "",
		"autosave_exists": false,
		"autosave_age_sec": -1,
		"log_warn": 0,
		"log_error": 0,
		"validation_run": false,
		"validation_issues": [],
		"validation_stamp": "",
	}


# ---------------------------------------------------------------------------
# Evaluation
# ---------------------------------------------------------------------------


## Turn a context snapshot into the ordered list of check rows the panel draws.
## Pure — same dictionary in, same rows out.
##
## Each row is:
##   id            stable key, used by tests and to keep row widgets in place
##   title         what is being checked
##   severity      Severity
##   value         the measurement, short enough to sit right-aligned
##   detail        one sentence naming the consequence, not restating the value
##   action_id     "" when the row has nothing actionable
##   action_label  the button's text
##   help          tooltip: what this measures and where the thresholds come from
static func evaluate(ctx: Dictionary) -> Array[Dictionary]:
	var checks: Array[Dictionary] = []
	checks.append(_check_level_root(ctx))
	checks.append(_check_geometry(ctx))
	checks.append(_check_bake(ctx))
	checks.append(_check_validation(ctx))
	checks.append(_check_materials(ctx))
	checks.append(_check_spawn(ctx))
	checks.append(_check_autosave(ctx))
	checks.append(_check_log(ctx))
	return checks


## Roll the rows up into the single light in the console header.
## UNKNOWN never drives the headline — a level that is not loaded is not a
## fault, and colouring it as one trains people to ignore the board.
static func summarise(checks: Array) -> Dictionary:
	var tally := {"ok": 0, "warn": 0, "problem": 0, "unknown": 0}
	var worst := Severity.OK
	var measured := 0
	for check in checks:
		var severity := int(check.get("severity", Severity.UNKNOWN))
		match severity:
			Severity.OK:
				tally["ok"] += 1
				measured += 1
			Severity.WARN:
				tally["warn"] += 1
				measured += 1
			Severity.PROBLEM:
				tally["problem"] += 1
				measured += 1
			_:
				tally["unknown"] += 1
		if severity != Severity.UNKNOWN and severity > worst:
			worst = severity
	var label := ""
	if measured == 0:
		worst = Severity.UNKNOWN
		label = "Nothing to check yet"
	elif tally["problem"] > 0:
		label = "%d %s" % [tally["problem"], _plural(tally["problem"], "problem", "problems")]
		if tally["warn"] > 0:
			label += ", %d to review" % tally["warn"]
	elif tally["warn"] > 0:
		label = "%d to review" % tally["warn"]
	else:
		label = "All clear"
	return {
		"severity": worst,
		"label": label,
		"ok": tally["ok"],
		"warn": tally["warn"],
		"problem": tally["problem"],
		"unknown": tally["unknown"],
		"measured": measured,
		"total": checks.size(),
	}


# ---------------------------------------------------------------------------
# Individual checks
# ---------------------------------------------------------------------------


static func _check_level_root(ctx: Dictionary) -> Dictionary:
	var help := (
		"HammerForge edits brushes that live under a LevelRoot node.\n"
		+ "Without one in the open scene there is nothing for the tools to write to."
	)
	if not ctx.get("has_root", false):
		return _row(
			"level_root",
			"Level root",
			Severity.PROBLEM,
			"Missing",
			"No LevelRoot in the open scene, so every tool below is inert.",
			help,
			"create_starter",
			"Create Starter Level"
		)
	return _row(
		"level_root",
		"Level root",
		Severity.OK,
		str(ctx.get("root_name", "LevelRoot")),
		"Tools are writing to this node.",
		help
	)


static func _check_geometry(ctx: Dictionary) -> Dictionary:
	var help := (
		"Live brushes plus entities. The editor re-solves brush geometry as you drag,\n"
		+ "so this count governs editing smoothness — not the baked mesh.\n"
		+ "Amber above %d, red above %d." % [GEOMETRY_WARN, GEOMETRY_PROBLEM]
	)
	if not ctx.get("has_root", false):
		return _row("geometry", "Geometry budget", Severity.UNKNOWN, "-", "No level loaded.", help)
	var brushes := int(ctx.get("brush_count", 0))
	var entities := int(ctx.get("entity_count", 0))
	var total := brushes + entities
	var value := (
		"%d brush%s, %d entit%s"
		% [brushes, "" if brushes == 1 else "es", entities, "y" if entities == 1 else "ies"]
	)
	var severity := Severity.OK
	var detail := "%d of a comfortable %d. Editing stays responsive." % [total, GEOMETRY_WARN]
	if total > GEOMETRY_PROBLEM:
		severity = Severity.PROBLEM
		detail = (
			"%d objects is past the %d where dragging starts to stutter. Split the level, or bake in chunks."
			% [total, GEOMETRY_PROBLEM]
		)
	elif total > GEOMETRY_WARN:
		severity = Severity.WARN
		detail = (
			"%d objects. Past %d the editor stays usable but bakes get noticeably slower."
			% [total, GEOMETRY_PROBLEM]
		)
	var action_id := ""
	var action_label := ""
	var recommended := float(ctx.get("recommended_chunk_size", 0.0))
	if recommended > 0.0 and not is_equal_approx(recommended, float(ctx.get("chunk_size", 0.0))):
		action_id = "apply_chunk_size"
		action_label = "Set chunk size %d" % int(recommended)
		detail += " Recommended chunk size for this level's extent is %d." % int(recommended)
	return _row(
		"geometry", "Geometry budget", severity, value, detail, help, action_id, action_label
	)


static func _check_bake(ctx: Dictionary) -> Dictionary:
	var help := (
		"Baking turns the draft brushes into the merged meshes and collision that\n"
		+ "actually ship. The viewport shows drafts; play mode shows the bake."
	)
	if not ctx.get("has_root", false):
		return _row("bake", "Bake", Severity.UNKNOWN, "-", "No level loaded.", help)
	var brushes := int(ctx.get("brush_count", 0))
	var baked := int(ctx.get("baked_count", 0))
	var dirty := int(ctx.get("dirty_brush_count", 0))
	var last_ms := int(ctx.get("last_bake_ms", 0))
	if brushes == 0 and baked == 0:
		return _row(
			"bake", "Bake", Severity.UNKNOWN, "Nothing yet", "Draw a brush to get started.", help
		)
	if baked == 0:
		return _row(
			"bake",
			"Bake",
			Severity.WARN,
			"Never baked",
			"Play mode has no geometry to run against until this level is baked once.",
			help,
			"bake",
			"Bake Now"
		)
	if dirty > 0:
		return _row(
			"bake",
			"Bake",
			Severity.WARN,
			"%d changed" % dirty,
			(
				"%d brush%s edited since the last bake, so play mode is showing older geometry."
				% [dirty, "" if dirty == 1 else "es"]
			),
			help,
			"bake",
			"Bake Now"
		)
	var detail := "The baked meshes match the drafts in the viewport."
	if last_ms > 0:
		detail += " Last bake took %d ms." % last_ms
	return _row("bake", "Bake", Severity.OK, "Up to date", detail, help)


static func _check_validation(ctx: Dictionary) -> Dictionary:
	var help := (
		"Scans for the faults that survive into a bake: zero-size and non-planar\n"
		+ "brushes, missing materials and shaders, subtracts that cut nothing.\n"
		+ "Amber for any issue, red at %d or more." % VALIDATION_PROBLEM
	)
	if not ctx.get("has_root", false):
		return _row("validation", "Level check", Severity.UNKNOWN, "-", "No level loaded.", help)
	if not ctx.get("validation_run", false):
		return _row(
			"validation",
			"Level check",
			Severity.UNKNOWN,
			"Not run",
			"Nothing has been scanned yet this session.",
			help,
			"validate",
			"Run Check"
		)
	var issues: Array = ctx.get("validation_issues", [])
	var stamp := str(ctx.get("validation_stamp", ""))
	if issues.is_empty():
		var clean_detail := "No faults found."
		if stamp != "":
			clean_detail += " Checked at %s." % stamp
		return _row("validation", "Level check", Severity.OK, "Clean", clean_detail, help)
	var severity := Severity.PROBLEM if issues.size() >= VALIDATION_PROBLEM else Severity.WARN
	var detail := str(issues[0])
	if issues.size() > 1:
		detail += "  (+%d more)" % (issues.size() - 1)
	return _row(
		"validation",
		"Level check",
		severity,
		"%d issue%s" % [issues.size(), "" if issues.size() == 1 else "s"],
		detail,
		help,
		"validate_fix",
		"Check + Fix"
	)


static func _check_materials(ctx: Dictionary) -> Dictionary:
	var help := (
		"The material palette every brush face indexes into. An empty palette is\n"
		+ "fine for greyboxing and fatal for a face-material bake, which has no\n"
		+ "palette entry to resolve each face against."
	)
	if not ctx.get("has_root", false):
		return _row(
			"materials", "Material palette", Severity.UNKNOWN, "-", "No level loaded.", help
		)
	var count := int(ctx.get("material_count", 0))
	if count == 0 and bool(ctx.get("bake_use_face_materials", false)):
		return _row(
			"materials",
			"Material palette",
			Severity.PROBLEM,
			"Empty",
			"Face-material bake is on with no palette, so the bake falls back to a flat surface.",
			help,
			"load_palette",
			"Load Palette"
		)
	if count == 0:
		return _row(
			"materials",
			"Material palette",
			Severity.WARN,
			"Empty",
			"Everything bakes with the default grey. Fine for greyboxing.",
			help,
			"load_palette",
			"Load Palette"
		)
	return _row(
		"materials",
		"Material palette",
		Severity.OK,
		"%d loaded" % count,
		"Faces can be assigned from the palette.",
		help
	)


static func _check_spawn(ctx: Dictionary) -> Dictionary:
	var help := (
		"Where Test Level drops the player. Without a player_start entity the run\n"
		+ "starts at the world origin, which is usually inside or below geometry."
	)
	if not ctx.get("has_root", false):
		return _row("spawn", "Player spawn", Severity.UNKNOWN, "-", "No level loaded.", help)
	var count := int(ctx.get("spawn_count", 0))
	if count > 0:
		return _row(
			"spawn",
			"Player spawn",
			Severity.OK,
			"%d point%s" % [count, "" if count == 1 else "s"],
			"Test Level starts here.",
			help
		)
	if bool(ctx.get("auto_spawn_player", false)):
		return _row(
			"spawn",
			"Player spawn",
			Severity.WARN,
			"Auto only",
			"No spawn point, so Test Level falls back to the world origin.",
			help,
			"add_spawn",
			"Add Spawn Point"
		)
	return _row(
		"spawn",
		"Player spawn",
		Severity.PROBLEM,
		"None",
		"No spawn point and auto-spawn is off, so Test Level starts with no player at all.",
		help,
		"add_spawn",
		"Add Spawn Point"
	)


static func _check_autosave(ctx: Dictionary) -> Dictionary:
	var help := (
		"HammerForge writes a .hflevel snapshot on a timer, separate from Godot's\n"
		+ "scene saving. It is what survives an editor crash mid-edit."
	)
	if not ctx.get("has_root", false):
		return _row("autosave", "Autosave", Severity.UNKNOWN, "-", "No level loaded.", help)
	if not bool(ctx.get("autosave_enabled", false)):
		return _row(
			"autosave",
			"Autosave",
			Severity.WARN,
			"Off",
			"Nothing recoverable if the editor stops between manual saves.",
			help,
			"enable_autosave",
			"Turn On"
		)
	var minutes := int(ctx.get("autosave_minutes", 0))
	var path := str(ctx.get("autosave_path", "?"))
	if not bool(ctx.get("autosave_exists", false)):
		return _row(
			"autosave",
			"Autosave",
			Severity.WARN,
			"No file yet",
			"On, every %d min, but nothing has been written to %s." % [minutes, path],
			help,
			"reveal_autosave",
			"Show Folder"
		)
	var age := int(ctx.get("autosave_age_sec", -1))
	var detail := "Writing to %s." % path
	if age >= 0:
		detail = "Last written %s ago, to %s." % [format_duration(age), path]
	return _row(
		"autosave",
		"Autosave",
		Severity.OK,
		"Every %d min" % minutes,
		detail,
		help,
		"reveal_autosave",
		"Show Folder"
	)


static func _check_log(ctx: Dictionary) -> Dictionary:
	var help := (
		"Warnings and errors HammerForge raised this editor session. These are the\n"
		+ "same messages Godot's Output panel buries among every other addon."
	)
	var warns := int(ctx.get("log_warn", 0))
	var errors := int(ctx.get("log_error", 0))
	if errors > 0:
		return _row(
			"log",
			"Session log",
			Severity.PROBLEM,
			"%d error%s" % [errors, "" if errors == 1 else "s"],
			"An operation failed this session. The Log tab has the message.",
			help,
			"open_log",
			"Open Log"
		)
	if warns > 0:
		return _row(
			"log",
			"Session log",
			Severity.WARN,
			"%d warning%s" % [warns, "" if warns == 1 else "s"],
			"Non-fatal, but worth reading before a bake.",
			help,
			"open_log",
			"Open Log"
		)
	return _row(
		"log", "Session log", Severity.OK, "Quiet", "No warnings or errors this session.", help
	)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


## "45s", "12m", "3h 20m", "2d" — short enough to sit inside a detail line.
static func format_duration(seconds: int) -> String:
	if seconds < 60:
		return "%ds" % maxi(seconds, 0)
	if seconds < 3600:
		return "%dm" % (seconds / 60)
	if seconds < 86400:
		var hours := seconds / 3600
		var minutes := (seconds % 3600) / 60
		if minutes == 0:
			return "%dh" % hours
		return "%dh %dm" % [hours, minutes]
	return "%dd" % (seconds / 86400)


static func _row(
	id: String,
	title: String,
	severity: int,
	value: String,
	detail: String,
	help: String,
	action_id: String = "",
	action_label: String = ""
) -> Dictionary:
	return {
		"id": id,
		"title": title,
		"severity": severity,
		"value": value,
		"detail": detail,
		"help": help,
		"action_id": action_id,
		"action_label": action_label,
	}


static func _plural(count: int, singular: String, plural: String) -> String:
	return singular if count == 1 else plural


static func _get_bool(target, property: String, fallback: bool) -> bool:
	var value = target.get(property)
	return fallback if value == null else bool(value)


static func _get_float(target, property: String, fallback: float) -> float:
	var value = target.get(property)
	return fallback if value == null else float(value)
