@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The Console's Log tab and the buffer behind it.
##
## `HFConsoleLog` is the one place a HammerForge warning is findable — Godot's
## own Output panel mixes every addon in the project into one stream. The buffer
## caps itself, collapses repeats, levels and filters, and hands the same text
## to Copy and to Save. Everything in here is a claim the Log tab makes to a
## reader who is trying to find out why a bake went wrong, so each one is worth
## measuring rather than trusting.

const LogType = preload("res://addons/hammerforge/hf_console_log.gd")
const LogViewType = preload("res://addons/hammerforge/ui/hf_console_log_view.gd")


func id() -> String:
	return "console-log"


func summary() -> String:
	return "what the Console log buffer keeps, drops, collapses and hands to Copy"


func run() -> void:
	_capacity_and_counts()
	_repeat_collapse()
	_filtering()
	_bbcode_escaping()
	await _view_against_buffer()


func _capacity_and_counts() -> void:
	var buffer = LogType.new()
	buffer.capacity = 10
	for i in range(200):
		buffer.info("message %d" % i, "cat")
	note("capacity", buffer.capacity)
	note("retained after 200 appends", buffer.size())
	note("dropped", buffer.dropped_count())
	note("session counts", buffer.counts())
	if buffer.size() > buffer.capacity:
		known(
			543,
			"the log buffer holds more entries than its own capacity",
			(
				(
					"capacity is %d and the buffer is holding %d; the summary line under the"
					+ " Log tab reports the capacity as 'buffer holds %d', so a reader counting"
					+ " lines sees more than the number the panel tells them it keeps"
				)
				% [buffer.capacity, buffer.size(), buffer.capacity]
			)
		)
	if buffer.size() + buffer.dropped_count() != 200:
		flag(
			"retained plus dropped does not add up to what was logged",
			"200 appended, %d retained, %d dropped" % [buffer.size(), buffer.dropped_count()]
		)


func _repeat_collapse() -> void:
	var buffer = LogType.new()
	for _i in range(5):
		buffer.warn("the same warning", "reconcile")
	var entries: Array = buffer.entries()
	note("rows after 5 identical warnings", entries.size())
	note("repeat count on the row", int(entries[0]["repeat"]) if entries.size() > 0 else -1)
	note("session counts", buffer.counts())
	var text: String = buffer.to_text()
	note("to_text", text)
	# A collapsed repeat is one row and five warnings. Whether the summary line
	# and the level toggles agree about which of those numbers they are showing
	# is the thing a reader reconciles against, so record both.
	if entries.size() == 1 and int(buffer.counts()["warn"]) != 5:
		flag(
			"a collapsed repeat is not counted the number of times it happened",
			"5 identical warnings collapsed to 1 row and the warn count reads %s" % buffer.counts()
		)


func _filtering() -> void:
	var buffer = LogType.new()
	buffer.info("brush created", "brush")
	buffer.warn("palette slot empty", "materials")
	buffer.error("bake failed", "bake")
	buffer.debug("drag tick", "drag")
	note("all four levels, mask 0xF", buffer.filtered(0xF).size())
	note("errors only", buffer.filtered(1 << LogType.Level.ERROR).size())
	note("search 'bake'", buffer.filtered(0xF, "bake").size())
	note(
		"search matches the category as well as the message",
		buffer.filtered(0xF, "materials").size()
	)
	note("search that matches nothing", buffer.filtered(0xF, "zzzz").size())
	note("empty search", buffer.filtered(0xF, "").size())
	note("whitespace-only search", buffer.filtered(0xF, "   ").size())
	if buffer.filtered(0xF, "   ").size() != 4:
		flag(
			"a filter field holding only spaces hides every line",
			(
				(
					"a reader who typed a space into the Log tab's filter sees %d of 4 lines and"
					+ " nothing says why"
				)
				% buffer.filtered(0xF, "   ").size()
			)
		)
	note("search is case-insensitive", buffer.filtered(0xF, "BAKE").size())


func _bbcode_escaping() -> void:
	var buffer = LogType.new()
	# Messages carry level names, material names and file paths, any of which can
	# hold a bracket. The Log tab renders through a RichTextLabel with bbcode on,
	# so anything that survives escaping is markup a level name can inject.
	var hostile := "[b]bold[/b] [color=red]red[/color] [url=http://x]link[/url]"
	buffer.info(hostile, "name")
	var entry: Dictionary = buffer.entries()[0]
	var escaped: String = LogType.escape_bbcode(str(entry["message"]))
	note("raw message", str(entry["message"]))
	note("escaped for the RichTextLabel", escaped)
	# `[` becomes `[lb]`, which is the literal bracket. A closing `]` on its own
	# is not markup, so what matters is whether any `[` survives unescaped.
	var surviving := 0
	var i := 0
	while i < escaped.length():
		if escaped[i] == "[":
			if escaped.substr(i, 4) != "[lb]":
				surviving += 1
			i += 4
		else:
			i += 1
	note("unescaped opening brackets left in the rendered line", surviving)
	if surviving > 0:
		flag(
			"a log message can still open a BBCode tag in the Log tab",
			"%d opening brackets survive escaping in %s" % [surviving, escaped]
		)


func _view_against_buffer() -> void:
	var buffer = LogType.new()
	var view = LogViewType.new()
	_tree.get_root().add_child(view)
	await frame()
	view.set_log(buffer)
	await frame()
	buffer.info("one", "a")
	buffer.warn("two", "b")
	buffer.error("three", "c")
	buffer.debug("four", "d")
	await frame()
	# Debug is off by default, so the view shows three of the four.
	note("buffer size", buffer.size())
	note("view summary", view._summary.text if view._summary else "<none>")
	note("empty hint visible", view._empty_hint.visible if view._empty_hint else null)
	view.isolate_level(LogType.Level.ERROR)
	await frame()
	note("after isolate_level(ERROR), summary", view._summary.text if view._summary else "<none>")
	buffer.clear()
	await frame()
	note("after clear, summary", view._summary.text if view._summary else "<none>")
	note("after clear, counts", buffer.counts())
	view.queue_free()
	await frame()
