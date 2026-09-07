@tool
class_name HFConsoleLog
extends RefCounted
## Session log behind the HammerForge Console's Log tab.
##
## Godot's own Output panel mixes every addon, every push_warning and every
## print in the project into one stream, so a HammerForge warning is only
## findable if you already know it happened. This keeps HammerForge's own
## messages in one place, levelled and filterable, and cheap enough that the
## editor can write to it on hot paths.
##
## One shared instance lives on the class (`HFConsoleLog.shared()`), so
## HFLog and the dock can append without holding a reference to the panel.
## The panel connects to `entry_appended` and must disconnect on teardown.

enum Level { DEBUG, INFO, WARN, ERROR }

const LEVEL_NAMES := ["DEBUG", "INFO", "WARN", "ERROR"]

## Entries beyond this are dropped oldest-first. A bake on a large level can
## emit hundreds of lines; the cap is what keeps an idle editor from growing a
## log until it matters.
const DEFAULT_CAPACITY := 600

## Trimming copies the array, so it happens once per SLACK entries rather than
## once per entry past the cap.
const TRIM_SLACK := 64

## A single message longer than this is truncated. A stack dump or a serialised
## dictionary pasted into a warning would otherwise stall the log view's text
## layout for as long as the entry stays in the buffer.
const MAX_MESSAGE_CHARS := 2000

signal entry_appended(entry: Dictionary)
## The last entry's repeat count changed instead of a new row being added.
signal entry_repeated(entry: Dictionary)
signal cleared

static var _shared: HFConsoleLog = null

var capacity: int = DEFAULT_CAPACITY
## Tests and headless runs can silence the buffer without unhooking callers.
var muted: bool = false

var _entries: Array[Dictionary] = []
var _counts := [0, 0, 0, 0]
var _dropped: int = 0
## Guards against a listener that logs from inside entry_appended, which would
## otherwise recurse until the editor stops responding.
var _appending: bool = false


## The process-wide buffer. Created on first use.
static func shared() -> HFConsoleLog:
	if _shared == null:
		_shared = HFConsoleLog.new()
	return _shared


## Drops the shared buffer. Tests use this to start from a known state.
static func reset_shared() -> void:
	_shared = null


static func level_name(level: int) -> String:
	if level < 0 or level >= LEVEL_NAMES.size():
		return "?"
	return LEVEL_NAMES[level]


func debug(message: String, category: String = "") -> void:
	append(Level.DEBUG, message, category)


func info(message: String, category: String = "") -> void:
	append(Level.INFO, message, category)


func warn(message: String, category: String = "") -> void:
	append(Level.WARN, message, category)


func error(message: String, category: String = "") -> void:
	append(Level.ERROR, message, category)


## Record one message. Consecutive identical messages collapse into a repeat
## count rather than filling the buffer — a reconcile loop that warns every
## frame stays readable, and stays one row.
func append(level: int, message: String, category: String = "") -> void:
	if muted or _appending:
		return
	# The bake thread pool logs, and both the entries array and the listening
	# UI belong to the main thread. Hand the call over rather than racing.
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		call_deferred("append", level, message, category)
		return
	var clamped := clampi(level, Level.DEBUG, Level.ERROR)
	var text := message.strip_edges()
	if text == "":
		return
	if text.length() > MAX_MESSAGE_CHARS:
		text = text.substr(0, MAX_MESSAGE_CHARS) + "... (truncated)"
	if not _entries.is_empty():
		var last: Dictionary = _entries[-1]
		if last["level"] == clamped and last["category"] == category and last["message"] == text:
			last["repeat"] = int(last["repeat"]) + 1
			last["msec"] = Time.get_ticks_msec()
			last["stamp"] = _timestamp()
			_counts[clamped] += 1
			_appending = true
			entry_repeated.emit(last)
			_appending = false
			return
	var entry := {
		"level": clamped,
		"category": category,
		"message": text,
		"stamp": _timestamp(),
		"msec": Time.get_ticks_msec(),
		"repeat": 1,
	}
	_entries.append(entry)
	_counts[clamped] += 1
	_trim()
	_appending = true
	entry_appended.emit(entry)
	_appending = false


## All retained entries, oldest first. The returned array is a copy; the
## dictionaries inside are shared, so callers must not mutate them.
func entries() -> Array[Dictionary]:
	return _entries.duplicate()


## Entries matching a level bitmask (bit N = Level N) and a case-insensitive
## substring of the message or category. An empty search matches everything.
func filtered(level_mask: int, search: String = "") -> Array[Dictionary]:
	var needle := search.strip_edges().to_lower()
	var out: Array[Dictionary] = []
	for entry in _entries:
		if not (level_mask & (1 << int(entry["level"]))):
			continue
		if needle != "":
			var hay := "%s %s" % [entry["category"], entry["message"]]
			if not hay.to_lower().contains(needle):
				continue
		out.append(entry)
	return out


## Per-level totals for the session, including entries already trimmed away.
## Keyed by level name so a caller does not have to know the enum order.
func counts() -> Dictionary:
	return {
		"debug": _counts[Level.DEBUG],
		"info": _counts[Level.INFO],
		"warn": _counts[Level.WARN],
		"error": _counts[Level.ERROR],
	}


## How many entries the cap has discarded this session.
func dropped_count() -> int:
	return _dropped


func size() -> int:
	return _entries.size()


func is_empty() -> bool:
	return _entries.is_empty()


## Clears retained entries and the session totals both.
func clear() -> void:
	_entries.clear()
	_counts = [0, 0, 0, 0]
	_dropped = 0
	cleared.emit()


## One entry rendered for the clipboard or a saved file.
static func format_entry(entry: Dictionary) -> String:
	var category := str(entry.get("category", ""))
	var prefix := "%s  %-5s" % [entry.get("stamp", ""), level_name(int(entry.get("level", 0)))]
	if category != "":
		prefix += "  [%s]" % category
	var line := "%s  %s" % [prefix, entry.get("message", "")]
	var repeat := int(entry.get("repeat", 1))
	if repeat > 1:
		line += "  (x%d)" % repeat
	return line


## The filtered buffer as plain text, for Copy and Save.
func to_text(level_mask: int = 0xF, search: String = "") -> String:
	var lines := PackedStringArray()
	for entry in filtered(level_mask, search):
		lines.append(format_entry(entry))
	return "\n".join(lines)


## Neutralises BBCode in a message so a RichTextLabel renders it verbatim.
## Messages carry file paths, entity names and material names, any of which can
## contain a bracket; without this, "[b]" in a level name would style the log.
static func escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")


func _timestamp() -> String:
	return Time.get_time_string_from_system()


func _trim() -> void:
	var limit := maxi(capacity, 1)
	if _entries.size() < limit + TRIM_SLACK:
		return
	var excess := _entries.size() - limit
	_entries = _entries.slice(excess)
	_dropped += excess
