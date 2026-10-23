@tool
class_name HFCrashJournal
extends RefCounted
## A short record of what this editor session did, kept on disk so that a crash
## leaves something behind (#1654).
##
## GDScript cannot catch the editor going down. What a plugin can do is write as
## it goes and notice afterwards. Each session writes one line per undo step and
## per bridge call to `journal/<pid>.jsonl`, flushed as it is written, and
## deletes the file when it closes cleanly. A journal whose process is no longer
## running was left by a session that died, and `collect()` turns it into a
## report folder under `crashes/`.
##
## Godot's editor keeps no log file of its own (file logging covers a running
## game), so a report has the journal and the levels, not the engine's output.
##
## Nothing here leaves the machine.

const ROOT := "user://hammerforge"
## Lines a journal keeps. It is rewritten to the newest of them once it holds
## twice as many.
const KEEP_LINES := 200
const MAX_REPORTS := 10
const MAX_REPORT_BYTES := 50 * 1024 * 1024
const MAX_REPORT_DAYS := 90
const MAX_LEVEL_BYTES := 20 * 1024 * 1024
## How much of a journal is read back. 200 lines fit with room to spare, and a
## journal grown past this by damage is read from its end.
const READ_BYTES := 64 * 1024
## The newest lines that say what a crash was doing. Two reports that end the
## same way are one crash seen twice.
const SIGNATURE_LINES := 5
const SECONDS_A_DAY := 86400

var root_dir := ""
var pid := 0
## The limits, as fields so a test can make them small.
var max_reports := MAX_REPORTS
var max_report_bytes := MAX_REPORT_BYTES
var max_level_bytes := MAX_LEVEL_BYTES

var _file: FileAccess = null
var _header := ""
var _stage_line := ""
var _lines := PackedStringArray()
var _last_version := -1


func _init(dir: String = ROOT, process_id: int = -1) -> void:
	root_dir = ProjectSettings.globalize_path(dir)
	pid = process_id if process_id >= 0 else OS.get_process_id()


func journal_dir() -> String:
	return root_dir.path_join("journal")


func crashes_dir() -> String:
	return root_dir.path_join("crashes")


func journal_path() -> String:
	return journal_dir().path_join("%d.jsonl" % pid)


func is_open() -> bool:
	return _file != null


## The project a journal belongs to. Two projects with one name share a user
## folder, and each reports only its own sessions.
static func project_key() -> String:
	return ProjectSettings.globalize_path("res://")


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------


## Begin this session's journal with a header naming the process, the project
## and both versions, and keep it open to add to. `OK`, or the open error.
func start(hammerforge_version: String = "") -> int:
	DirAccess.make_dir_recursive_absolute(journal_dir())
	_file = FileAccess.open(journal_path(), FileAccess.WRITE)
	if _file == null:
		return FileAccess.get_open_error()
	_header = _encode(
		{
			"kind": "session",
			"t": _now(),
			"pid": pid,
			"project": project_key(),
			"hammerforge": hammerforge_version,
			"godot": str(Engine.get_version_info().get("string", "")),
		}
	)
	_lines.clear()
	_file.store_line(_header)
	_file.close()
	return _reopen()


## Open the journal to add to it. Inside the editor, a file opened to write is
## written to a `.tmp` beside it and only moved into place when it closes, so a
## crash left that and no journal. A file opened to read and write is written
## in place.
func _reopen() -> int:
	_file = FileAccess.open(journal_path(), FileAccess.READ_WRITE)
	if _file == null:
		return FileAccess.get_open_error()
	_file.seek_end()
	return OK


## How far start up or shut down got.
func stage(stage_name: String) -> void:
	_stage_line = _write({"kind": "stage", "name": stage_name})


## One undo step. A version lower than the last one is an undo.
func step(action_name: String, version: int, brushes: int, level: String) -> void:
	var entry := {
		"kind": "step",
		"name": action_name,
		"version": version,
		"brushes": brushes,
		"level": level,
	}
	if _last_version >= 0 and version < _last_version:
		entry["undo"] = true
	_last_version = version
	_write(entry)


## One call over the agent bridge.
func bridge(method: String, ok: bool, code: String) -> void:
	_write({"kind": "bridge", "name": method, "ok": ok, "code": code})


## A clean close: the journal goes.
func finish() -> void:
	if _file:
		_file.close()
		_file = null
	if FileAccess.file_exists(journal_path()):
		DirAccess.remove_absolute(journal_path())


func _write(entry: Dictionary) -> String:
	if _file == null:
		return ""
	entry["t"] = _now()
	var line := _encode(entry)
	_lines.append(line)
	if _lines.size() >= KEEP_LINES * 2:
		_lines = _lines.slice(_lines.size() - KEEP_LINES)
		_rewrite()
	else:
		_file.store_line(line)
		_file.flush()
	return line


## The newest lines, written beside the old file and moved over it, so a crash
## while trimming still leaves a journal.
func _rewrite() -> void:
	var text := PackedStringArray([_header])
	# Where start up got to stays, however many steps came after it.
	if _stage_line != "" and not _lines.has(_stage_line):
		text.append(_stage_line)
	text.append_array(_lines)
	_file.close()
	_file = null
	HFLevelIO.write_bytes_atomic(journal_path(), ("\n".join(text) + "\n").to_utf8_buffer())
	_reopen()


## JSON in plain ASCII, so it reads back through the ASCII decoder, which never
## complains about a damaged line.
static func _encode(entry: Dictionary) -> String:
	var text := JSON.stringify(entry)
	var plain := true
	for i in text.length():
		if text.unicode_at(i) > 126:
			plain = false
			break
	if plain:
		return text
	var out := ""
	for i in text.length():
		var code := text.unicode_at(i)
		if code <= 126:
			out += text[i]
		elif code <= 0xFFFF:
			out += "\\u%04x" % code
		else:
			code -= 0x10000
			out += "\\u%04x\\u%04x" % [0xD800 + (code >> 10), 0xDC00 + (code & 0x3FF)]
	return out


static func _now() -> float:
	return Time.get_unix_time_from_system()


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------


## What a journal holds, read without trusting it: its session line, the entries
## that parse, and how many lines did not.
static func read_journal(path: String) -> Dictionary:
	var result := {"session": {}, "entries": [], "unreadable": 0, "bytes": 0}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	var length := file.get_length()
	result["bytes"] = length
	var head := _lines_of(file.get_buffer(mini(length, 4096)))
	if not head.is_empty():
		var session := _parse(head[0])
		if str(session.get("kind", "")) == "session":
			result["session"] = session
	var begin := maxi(0, length - READ_BYTES)
	file.seek(begin)
	var tail := _lines_of(file.get_buffer(length - begin))
	file.close()
	# A tail read from the middle of a file starts inside a line.
	if begin > 0 and not tail.is_empty():
		tail.remove_at(0)
	var entries: Array = []
	for line in tail:
		if line == "":
			continue
		var entry := _parse(line)
		if entry.is_empty():
			result["unreadable"] += 1
		elif str(entry.get("kind", "")) != "session":
			entries.append(entry)
	result["entries"] = entries
	return result


## The lines of `bytes`, read as ASCII. The ASCII decoder takes any byte with no
## error, where the UTF-8 one prints one for a damaged line. A journal is written
## in ASCII, so nothing in it is lost this way.
static func _lines_of(bytes: PackedByteArray) -> PackedStringArray:
	var lines := PackedStringArray()
	var begin := 0
	for i in bytes.size():
		if bytes[i] == 10:
			lines.append(bytes.slice(begin, i).get_string_from_ascii().strip_edges())
			begin = i + 1
	if begin < bytes.size():
		lines.append(bytes.slice(begin).get_string_from_ascii().strip_edges())
	return lines


static func _parse(line: String) -> Dictionary:
	if line == "":
		return {}
	# An instance parse, which reports a bad line by its return value. The
	# static one prints an error for it.
	var json := JSON.new()
	if json.parse(line) != OK or not (json.data is Dictionary):
		return {}
	return json.data


static func _read_text(path: String, limit: int) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var bytes := file.get_buffer(mini(file.get_length(), limit))
	file.close()
	return "\n".join(_lines_of(bytes))


# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------


## Turn every journal a dead session left into a report, and return the reports
## made or counted again. `is_running(pid)` says whether a process is alive;
## without one, `process_alive()` asks the system.
func collect(is_running: Callable = Callable()) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	var folder := journal_dir()
	if not DirAccess.dir_exists_absolute(folder):
		return reports
	for file_name in DirAccess.get_files_at(folder):
		if file_name.get_extension() != "jsonl" or not file_name.get_basename().is_valid_int():
			continue
		var other := file_name.get_basename().to_int()
		if other == pid:
			continue
		var running: bool = (
			is_running.call(other) == true if is_running.is_valid() else process_alive(other)
		)
		if running:
			continue
		var path := folder.path_join(file_name)
		var read := read_journal(path)
		var project := str((read["session"] as Dictionary).get("project", ""))
		if project != "" and project != project_key():
			continue
		var report := _report(path, read)
		if report.is_empty():
			continue
		reports.append(report)
		DirAccess.remove_absolute(path)
	if not reports.is_empty():
		prune()
	return reports


## Whether a process is alive, by its id.
##
## Not `OS.is_process_running()`: that knows only the processes this one
## started, so it called every other editor dead, and on Linux it prints an error
## for each. A check that cannot run counts the process alive, so a journal is
## never taken from a session that may still be writing it.
static func process_alive(process_id: int) -> bool:
	if process_id <= 0:
		return false
	match OS.get_name():
		"Windows":
			var output: Array = []
			var args := ["/FI", "PID eq %d" % process_id, "/NH", "/FO", "CSV"]
			if OS.execute("tasklist", args, output) != 0:
				return true
			return "".join(output).contains('"%d"' % process_id)
		"Linux", "Android":
			return DirAccess.dir_exists_absolute("/proc/%d" % process_id)
		_:
			return OS.execute("kill", ["-0", str(process_id)]) == 0


func _report(journal: String, read: Dictionary) -> Dictionary:
	var entries: Array = read["entries"]
	var session: Dictionary = read["session"]
	var signature := _signature(entries)
	var now := _now()
	var seen_before := _folder_with_signature(signature)
	if seen_before != "":
		var again := read_report(seen_before)
		again["count"] = int(_number(again.get("count"), 1.0)) + 1
		again["last_seen"] = now
		_store_text(seen_before.path_join("report.json"), _encode_report(again))
		again["folder"] = seen_before
		return again
	var folder := _new_folder()
	if folder == "":
		return {}
	# The journal as it was read, so a damaged one is not copied whole.
	var kept := PackedStringArray()
	if not session.is_empty():
		kept.append(_encode(session))
	for entry in entries:
		kept.append(_encode(entry))
	_store_text(folder.path_join("journal.jsonl"), "\n".join(kept) + "\n")
	var written := int(FileAccess.get_modified_time(journal))
	var report := {
		"count": 1,
		"first_seen": now,
		"last_seen": now,
		"signature": signature,
		"pid": int(_number(session.get("pid"), journal.get_file().get_basename().to_int())),
		"session_started": _number(session.get("t"), 0.0),
		"last_written": written,
		"hammerforge": str(session.get("hammerforge", "")),
		"godot": str(session.get("godot", "")),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"adapter":
		(
			(
				"%s %s"
				% [
					RenderingServer.get_video_adapter_vendor(),
					RenderingServer.get_video_adapter_name()
				]
			)
			. strip_edges()
		),
		"renderer": RenderingServer.get_current_rendering_method(),
		"stage": _last_name(entries, "stage"),
		"last_step": _last_name(entries, "step"),
		"last_bridge_call": _last_name(entries, "bridge"),
		"unreadable_lines": int(read["unreadable"]),
		"journal_bytes": int(read["bytes"]),
		"levels": _copy_levels(folder, entries),
	}
	_store_text(folder.path_join("report.json"), _encode_report(report))
	report["folder"] = folder
	return report


## The newest lines' kinds and names, which is what a repeat has in common.
static func _signature(entries: Array) -> String:
	var parts := PackedStringArray()
	for entry in entries.slice(maxi(0, entries.size() - SIGNATURE_LINES)):
		var part := "%s:%s" % [str(entry.get("kind", "")), str(entry.get("name", ""))]
		if _flag(entry.get("undo")):
			part += ":undo"
		if str(entry.get("kind", "")) == "bridge" and not _flag(entry.get("ok")):
			part += ":" + str(entry.get("code", ""))
		parts.append(part)
	return " | ".join(parts)


static func _last_name(entries: Array, kind: String) -> String:
	for i in range(entries.size() - 1, -1, -1):
		if str(entries[i].get("kind", "")) == kind:
			return str(entries[i].get("name", ""))
	return ""


func _folder_with_signature(signature: String) -> String:
	if signature == "":
		return ""
	for folder in report_folders():
		if str(read_report(folder).get("signature", "")) == signature:
			return folder
	return ""


func _new_folder() -> String:
	var stamp := Time.get_datetime_string_from_system().replace("T", "-").replace(":", "")
	var folder := crashes_dir().path_join(stamp)
	var attempt := 2
	while DirAccess.dir_exists_absolute(folder) and attempt < 100:
		folder = crashes_dir().path_join("%s-%d" % [stamp, attempt])
		attempt += 1
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return ""
	return folder


## A copy of the newest autosave of each level the journal names. A copy over
## the limit is left out and named.
func _copy_levels(folder: String, entries: Array) -> Array:
	var named := {}
	for entry in entries:
		var level := str(entry.get("level", ""))
		if level != "":
			named[level] = true
	var levels: Array = []
	for level in named.keys():
		var source := newest_autosave(level)
		if source == "":
			levels.append({"level": level, "copy": "", "note": "no autosave found"})
			continue
		var size := _size_of(source)
		if size > max_level_bytes:
			levels.append(
				{
					"level": level,
					"copy": "",
					"note": "left out: %.1f MB is over the limit" % (size / 1048576.0)
				}
			)
			continue
		var target_dir := folder.path_join("levels")
		DirAccess.make_dir_recursive_absolute(target_dir)
		if DirAccess.copy_absolute(source, target_dir.path_join(source.get_file())) != OK:
			levels.append({"level": level, "copy": "", "note": "could not copy %s" % source})
			continue
		levels.append({"level": level, "copy": "levels/" + source.get_file(), "from": source})
	return levels


## The newest of a level's autosave file and its history copies, or "".
static func newest_autosave(level: String) -> String:
	var main := ProjectSettings.globalize_path(level)
	var best := ""
	var best_time := -1
	if FileAccess.file_exists(main):
		best = main
		best_time = int(FileAccess.get_modified_time(main))
	var history := main.get_base_dir().path_join("autosave_history")
	if DirAccess.dir_exists_absolute(history):
		var prefix := main.get_file().get_basename() + "_"
		for file_name in DirAccess.get_files_at(history):
			var tail := file_name.trim_prefix(prefix)
			# What follows the name is a timestamp, so it starts with a year.
			if (
				not file_name.begins_with(prefix)
				or file_name.get_extension() != "hflevel"
				or not tail.left(4).is_valid_int()
			):
				continue
			var path := history.path_join(file_name)
			var modified := int(FileAccess.get_modified_time(path))
			if modified > best_time:
				best = path
				best_time = modified
	return best


## Report folders, newest seen first.
func report_folders() -> Array[String]:
	var folders: Array[String] = []
	if not DirAccess.dir_exists_absolute(crashes_dir()):
		return folders
	var seen := {}
	for sub in DirAccess.get_directories_at(crashes_dir()):
		var folder := crashes_dir().path_join(sub)
		folders.append(folder)
		seen[folder] = _number(read_report(folder).get("last_seen"), 0.0)
	folders.sort_custom(func(a: String, b: String) -> bool: return seen[a] > seen[b])
	return folders


## The `report.json` in a report folder, or `{}` when it is missing or damaged.
static func read_report(folder: String) -> Dictionary:
	return _parse(_read_text(folder.path_join("report.json"), 256 * 1024).replace("\n", " "))


## Keep 10 reports, 50 MB in all, none older than 90 days. The newest stays
## whatever its size.
func prune() -> void:
	var total := 0
	var now := _now()
	var index := 0
	for folder in report_folders():
		var size := _tree_size(folder)
		var age := now - _number(read_report(folder).get("last_seen"), 0.0)
		if (
			index > 0
			and (
				index >= max_reports
				or age > MAX_REPORT_DAYS * SECONDS_A_DAY
				or total + size > max_report_bytes
			)
		):
			_remove_tree(folder)
			continue
		total += size
		index += 1


## What Copy Report puts on the clipboard: the report and the journal's last
## lines.
static func report_text(folder: String) -> String:
	var lines := PackedStringArray()
	lines.append("HammerForge crash report, %s" % folder)
	lines.append(_read_text(folder.path_join("report.json"), 256 * 1024))
	var journal := _read_text(folder.path_join("journal.jsonl"), READ_BYTES).split("\n", false)
	lines.append("")
	lines.append("Last lines of the journal:")
	lines.append_array(journal.slice(maxi(0, journal.size() - 20)))
	return "\n".join(lines)


static func _encode_report(report: Dictionary) -> String:
	var copy := report.duplicate()
	copy.erase("folder")
	return _encode(copy)


## A number read from a file, or `fallback` for anything else. A damaged file
## can hold any type where a number was written, and `float()` of a dictionary
## is a script error.
static func _number(value: Variant, fallback: float) -> float:
	return float(value) if value is int or value is float else fallback


## Only a real switch is on. Comparing a damaged number with `true` is a script
## error.
static func _flag(value: Variant) -> bool:
	return value is bool and value


static func _store_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()


static func _size_of(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return size


static func _tree_size(folder: String) -> int:
	var total := 0
	for file_name in DirAccess.get_files_at(folder):
		total += _size_of(folder.path_join(file_name))
	for sub in DirAccess.get_directories_at(folder):
		total += _tree_size(folder.path_join(sub))
	return total


static func _remove_tree(folder: String) -> void:
	for file_name in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file_name))
	for sub in DirAccess.get_directories_at(folder):
		_remove_tree(folder.path_join(sub))
	DirAccess.remove_absolute(folder)
