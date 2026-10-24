@tool
class_name HFProblemReport
extends RefCounted
## A bug report as the repository's bug form takes it, and the link that opens
## the form filled in (#1655).
##
## GitHub fills an issue form from the URL, one query parameter per field id.
## Browsers and servers refuse a very long URL, so a report past `URL_LIMIT`
## opens the form with its title and versions only and goes whole on the
## clipboard instead. HammerForge sends nothing: the person reads the form in
## the browser and submits it there.

const ISSUE_URL := "https://github.com/saworbit/hammerforge/issues/new"
const TEMPLATE := "bug_report.yml"
const URL_LIMIT := 2000
const TITLE_LIMIT := 80

## The bug form's field ids, in the form's order.
const FIELDS := [
	"what-happened",
	"expected",
	"repro",
	"godot-version",
	"os",
	"commit",
	"logs",
	"crash-report",
]
## What a link too long for a URL keeps.
const SHORT_FIELDS := ["godot-version", "os", "commit"]
const HEADINGS := {
	"what-happened": "What happened",
	"expected": "What you expected",
	"repro": "Steps to reproduce",
	"godot-version": "Godot version",
	"os": "Operating system",
	"commit": "HammerForge commit or version",
	"logs": "Relevant output",
	"crash-report": "Crash report or bridge calls",
}


## `{"url": ..., "clipboard": ...}`: the link, and the whole report as text when
## it did not fit in the link, or "" when it did.
static func link(report: Dictionary) -> Dictionary:
	var full := url_for(report, FIELDS)
	if full.length() <= URL_LIMIT:
		return {"url": full, "clipboard": ""}
	return {"url": url_for(report, SHORT_FIELDS), "clipboard": as_text(report)}


## The link with `fields` of the report filled in, and its title.
static func url_for(report: Dictionary, fields: Array) -> String:
	var parts := PackedStringArray(["template=%s" % TEMPLATE])
	var title := str(report.get("title", ""))
	if title != "":
		parts.append("title=%s" % title.uri_encode())
	for field in fields:
		var value := str(report.get(field, ""))
		if value != "":
			parts.append("%s=%s" % [field, value.uri_encode()])
	return ISSUE_URL + "?" + "&".join(parts)


## The report as text, one heading a field, for pasting into the form.
static func as_text(report: Dictionary) -> String:
	var lines := PackedStringArray()
	var title := str(report.get("title", ""))
	if title != "":
		lines.append(title)
		lines.append("")
	for field in FIELDS:
		var value := str(report.get(field, ""))
		if value == "":
			continue
		lines.append("### %s" % HEADINGS[field])
		lines.append(value)
		lines.append("")
	return "\n".join(lines).strip_edges() + "\n"


## The plugin's version, from `plugin.cfg`.
static func hammerforge_version() -> String:
	var config := ConfigFile.new()
	if config.load("res://addons/hammerforge/plugin.cfg") != OK:
		return ""
	return str(config.get_value("plugin", "version", ""))


## A title from what happened: its first line, cut short.
static func title_from(what_happened: String) -> String:
	var first := what_happened.strip_edges().get_slice("\n", 0).strip_edges()
	if first == "":
		return "[Bug] "
	if first.length() > TITLE_LIMIT:
		first = first.left(TITLE_LIMIT - 3).strip_edges() + "..."
	return "[Bug] " + first


## A path as far as it is the person's own business: the project and the user
## folder by their Godot names, a home folder as `~`.
static func scrub(text: String) -> String:
	var out := text
	var pairs := [
		[ProjectSettings.globalize_path("res://"), "res://"],
		[ProjectSettings.globalize_path("user://"), "user://"],
	]
	for variable in ["USERPROFILE", "HOME"]:
		var home := OS.get_environment(variable)
		if home != "":
			pairs.append([home, "~"])
	for pair in pairs:
		var from := str(pair[0]).trim_suffix("/").trim_suffix("\\")
		if from.length() < 3:
			continue
		var to := str(pair[1]).trim_suffix("/")
		# Either slash, as Windows paths reach a log both ways.
		for form in [from, from.replace("/", "\\"), from.replace("\\", "/")]:
			out = out.replace(form, to)
	return out
