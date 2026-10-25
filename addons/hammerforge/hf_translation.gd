@tool
class_name HFTranslation
extends RefCounted
## HammerForge's words in the editor's language (#1702).
##
## Its catalogs live in a translation domain of their own, `hammerforge`, so they
## never change one of the editor's words, and the editor's catalogs never change
## one of HammerForge's. Every surface the plugin puts in the editor's tree is
## given the domain with `adopt()`, and its controls look their text up there by
## themselves. Text put together in code goes through `t()` or `tn()` first, with
## named placeholders filled in after:
## `HFTranslation.t("Repeat: {command}").format({"command": label})`.
##
## Any `.po` file in `translations/` loads when the plugin starts, and a word a
## catalog does not have stays English. The Console's log, the bridge's replies
## and error codes are never looked up, so a bug report and an agent read the
## same words in every language. `docs/translating.md` is the contributor's page.

const DOMAIN := "hammerforge"
const CATALOGS := "res://addons/hammerforge/translations"
const EXTENSIONS := ["po", "mo"]

## Where `load_catalogs()` reads, and the language it shows: the editor's when
## empty. A test points these at its own and puts them back.
static var folder := CATALOGS
static var language := ""


static func domain() -> TranslationDomain:
	return TranslationServer.get_or_add_domain(DOMAIN)


## Every catalog in `folder` into the domain, shown in `language` or else the
## editor's. Returns the locales loaded. The plugin calls this before it builds a
## control, since a control looks its text up as it enters the tree.
static func load_catalogs() -> PackedStringArray:
	var into := domain()
	into.clear()
	into.set_locale_override(language if language != "" else TranslationServer.get_tool_locale())
	var locales := PackedStringArray()
	if not DirAccess.dir_exists_absolute(folder):
		return locales
	var files := DirAccess.get_files_at(folder)
	files.sort()
	for file in files:
		if not EXTENSIONS.has(file.get_extension()):
			continue
		var catalog = ResourceLoader.load(
			folder.path_join(file), "", ResourceLoader.CACHE_MODE_IGNORE
		)
		if catalog is Translation:
			into.add_translation(catalog)
			locales.append((catalog as Translation).locale)
	return locales


## Take the catalogs out again, as the plugin stops.
static func unload() -> void:
	if TranslationServer.has_domain(DOMAIN):
		TranslationServer.remove_domain(DOMAIN)


## Put `node`, and everything under it, in the domain. For a surface the plugin
## adds to the editor's own tree, which would otherwise look its words up in the
## editor's catalogs and translate some of them.
static func adopt(node: Node) -> void:
	if node != null:
		node.set_translation_domain(DOMAIN)


## `text` in the language shown.
static func t(text: String, context := "") -> String:
	return String(domain().translate(text, context))


## `one` or `many` in the language shown, by `count` and that language's plural
## rules. Put the number in with a `{count}` placeholder, never by gluing it on.
static func tn(one: String, many: String, count: int, context := "") -> String:
	return String(domain().translate_plural(one, many, count, context))
