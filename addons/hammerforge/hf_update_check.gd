@tool
class_name HFUpdateCheck
extends RefCounted
## Whether a newer HammerForge is out, and whether to ask at all (#1656).
##
## The answer comes from the Asset Library, which is how most people install
## HammerForge. Its edits are moderated, so it can trail a GitHub release by
## days, and that is the right lag: the notice never points at a version the
## person cannot get the usual way.
##
## It asks at most once a day, only when the editor is online and its own update
## check is on, only when HammerForge's switch is on, and never from a build
## whose version ends in `-dev`. The request carries nothing beyond what any HTTP
## request must. HammerForge never downloads or installs anything.

const ASSET_URL := "https://godotengine.org/asset-library/api/asset/5449"
const RELEASE_URL := "https://github.com/saworbit/hammerforge/releases/tag/v%s"
const TIMEOUT_SECONDS := 10.0
const DAY_SECONDS := 86400
const LATER_DAYS := 3

## The preferences it keeps.
const ENABLED := "check_for_updates"
const LAST_CHECKED := "update_last_checked"
const SKIPPED := "update_skip_version"
const LATER_UNTIL := "update_later_until"


## A version as numbers: "v0.10.2-rc1" is [0, 10, 2]. What follows a "-" or a
## "+" is left out.
static func numbers(version: String) -> Array[int]:
	var core := version.strip_edges().trim_prefix("v").get_slice("-", 0).get_slice("+", 0)
	var out: Array[int] = []
	for part in core.split("."):
		out.append(part.to_int() if part.is_valid_int() else 0)
	return out


## Whether `latest` is a newer version than `current`, as versions: 0.10.0 is
## newer than 0.9.0.
static func newer(latest: String, current: String) -> bool:
	var a := numbers(latest)
	var b := numbers(current)
	for i in maxi(a.size(), b.size()):
		var x := a[i] if i < a.size() else 0
		var y := b[i] if i < b.size() else 0
		if x != y:
			return x > y
	return false


## Why it must not ask now, or "" when it may.
static func why_not(
	current: String, prefs, editor_online: bool, editor_checks: bool, now: float
) -> String:
	if current == "" or current.contains("-dev"):
		return "a development build"
	if not editor_online:
		return "the editor is offline"
	if not editor_checks:
		return "the editor's update check is off"
	if prefs != null and prefs.get_pref(ENABLED, true) != true:
		return "turned off in Settings"
	var last := _number(prefs.get_pref(LAST_CHECKED, 0.0) if prefs != null else 0.0)
	if now - last < DAY_SECONDS:
		return "asked within the last day"
	return ""


## The Asset Library's version from its answer, or "" when the answer is not one.
static func version_from(body: PackedByteArray) -> String:
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not (json.data is Dictionary):
		return ""
	var version: Variant = json.data.get("version_string")
	if not (version is String) or numbers(version).is_empty():
		return ""
	return version


## What the Status board shows, `{"latest", "current"}`, or {} when there is
## nothing to say: not newer, skipped, or put off until later.
static func notice_for(latest: String, current: String, prefs, now: float) -> Dictionary:
	if latest == "" or not newer(latest, current):
		return {}
	if prefs != null:
		if str(prefs.get_pref(SKIPPED, "")) == latest:
			return {}
		if now < _number(prefs.get_pref(LATER_UNTIL, 0.0)):
			return {}
	return {"latest": latest, "current": current}


static func _number(value: Variant) -> float:
	return float(value) if value is int or value is float else 0.0
