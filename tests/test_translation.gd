extends GutTest

## HammerForge's words can be translated without touching the editor's (#1702):
## its own translation domain on every surface it adds to the editor, catalogs
## from `translations/` in the editor's language, the palette in that language,
## and a POT that is kept current.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const PotCatalog = preload("res://tools/pot_catalog.gd")
const HFTranslationScript = preload("res://addons/hammerforge/hf_translation.gd")
const HFCommandRegistryScript = preload("res://addons/hammerforge/hf_command_registry.gd")
const Toasts = preload("res://addons/hammerforge/ui/hf_toast.gd")

const SPANISH := "res://tests/translations"
const PLACEHOLDER := "\\{[A-Za-z_][A-Za-z_0-9]*\\}"
const PRINTF := "%[-+ 0#]*[0-9]*(?:\\.[0-9]+)?[sdifxXcv%]"

var rig := PluginRig.new()


func before_all():
	HFTranslationScript.folder = SPANISH
	HFTranslationScript.language = "es"
	await rig.bring_up(self)


func after_all():
	await rig.take_down()
	HFTranslationScript.folder = HFTranslationScript.CATALOGS
	HFTranslationScript.language = ""
	HFTranslationScript.unload()


func test_the_committed_pot_is_what_the_addon_builds():
	var committed := FileAccess.get_file_as_string(PotCatalog.PATH).replace("\r\n", "\n")
	var built := PotCatalog.build()
	if committed == built:
		pass_test("hammerforge.pot is current")
		return
	var have := committed.split("\n")
	var want := built.split("\n")
	var first := 0
	while first < mini(have.size(), want.size()) and have[first] == want[first]:
		first += 1
	fail_test(
		(
			"hammerforge.pot is not what the addon builds, from line %d:\n  committed: %s\n  built:     %s\nRun: %s"
			% [
				first + 1,
				have[first] if first < have.size() else "(end)",
				want[first] if first < want.size() else "(end)",
				PotCatalog.REGENERATE,
			]
		)
	)


func test_a_word_is_found_as_a_control_would_show_it():
	var source := (
		"\n"
		. join(
			[
				'button.text = "Bake"',
				"label.tooltip_text = (",
				'	"Two lines"',
				'	+ " joined"',
				")",
				'mode.text = "Add" if adding else "Subtract"',
				'menu.add_item("Copy", 3)',
				'tree_item.set_text(0, "Name")',
				'tabs.set_tab_title(1, "Paint")',
				'HFTranslation.t("Clip", "verb")',
				'HFTranslationType.tn("{count} brush", "{count} brushes", n)',
				'# label.text = "In a comment"',
				'count.text = "%d brushes" % n',
				'if button.text == "Compared":',
				'var text = "A variable"',
				'func make(text = "A default"):',
				'node.name = "NotShown"',
				'grab.text = &"AStringName"',
				'x.t("NotOurs")',
			]
		)
	)
	var found: Array = PotCatalog.script_words(source)
	var ids: Array = found.map(func(word): return word[0])
	assert_eq(
		ids,
		[
			"Bake",
			"Two lines joined",
			"Add",
			"Subtract",
			"Copy",
			"Name",
			"Paint",
			"Clip",
			"{count} brush"
		]
	)
	assert_eq(found[7], ["Clip", "", "verb"], "a context is kept")
	assert_eq(found[8], ["{count} brush", "{count} brushes", ""], "so is a plural")


func test_a_toast_or_a_status_line_is_found_as_it_would_show():
	var source := (
		"\n"
		. join(
			[
				'dock.show_toast("Saved", 1)',
				'_set_status("Baking")',
				'_say(plugin, "Grouped", 0)',
				'_toast(plugin, "Stamped", 1)',
				'root.user_message.emit("Nothing to paste", 1)',
				"root.emit_signal(",
				'	"user_message", "Pick a mesh first", 1',
				")",
				'show_toast("%d placed" % n)',
				'root.emit_signal("user_message", "Failed: " + why, 2)',
				'root.emit_signal("bake_finished", "NotShown")',
				'done.emit("NotShown")',
			]
		)
	)
	var ids: Array = PotCatalog.script_words(source).map(func(word): return word[0])
	assert_eq(
		ids, ["Saved", "Baking", "Grouped", "Stamped", "Nothing to paste", "Pick a mesh first"]
	)


func test_a_message_stays_english_for_the_log_and_shows_in_the_language():
	HFTranslationScript.load_catalogs()
	var english := HFTranslationScript.message("Repeat: {command}", {"command": "Hollow"})
	assert_eq(english, "Repeat: Hollow", "the log and the bridge read English")
	assert_eq(HFTranslationScript.shown(english), "Repetir: Hollow", "a toast shows Spanish")
	var counted := HFTranslationScript.message_n("{count} brush", "{count} brushes", 3)
	assert_eq(counted, "3 brushes")
	assert_eq(HFTranslationScript.shown(counted), "3 pinceles")
	assert_eq(HFTranslationScript.shown("Not a message"), "Not a message")
	var toasts: Node = add_child_autofree(Toasts.new())
	toasts.show_toast(english)
	assert_eq(toasts.get_child(0).get_child(0).text, "Repetir: Hollow", "the toast's label")
	var source := (
		'x(HFTranslationType.message("Saved {file}", {"file": f}))\n'
		+ 'x(HFTranslation.message_n("{count} cut", "{count} cuts", n))'
	)
	var found: Array = PotCatalog.script_words(source)
	assert_eq(found, [["Saved {file}", "", ""], ["{count} cut", "{count} cuts", ""]])


func test_every_surface_the_plugin_adds_to_the_editor_is_in_the_domain():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var plugin: Node = rig.plugin
	for field in [
		"dock",
		"hud",
		"console_panel",
		"console_strip",
		"_hotkey_palette",
		"_context_toolbar",
		"_quick_property",
		"_selection_filter",
		"_viewport_context_menu",
	]:
		var surface = plugin.get(field)
		assert_true(surface is Node, "%s is built" % field)
		if surface is Node:
			assert_eq(surface.get_translation_domain(), StringName("hammerforge"), field)
	var dialog := ConfirmationDialog.new()
	plugin._add_confirmable_dialog(dialog)
	assert_eq(dialog.get_translation_domain(), StringName("hammerforge"), "a dialog")
	dialog.free()
	var editor: Control = plugin.get_editor_interface().get_base_control()
	assert_ne(editor.get_translation_domain(), StringName("hammerforge"), "the editor's own is not")


func test_a_catalog_changes_a_dock_label_in_its_language_and_nothing_of_the_editors():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var button: Button = rig.plugin.dock.find_child("CreateStarter", true, false)
	assert_not_null(button)
	assert_eq(button.text, "Create Starter Level", "the label itself stays English")
	assert_eq(button.atr(button.text), "Crear un nivel listo para usar", "what it shows")
	var english := Button.new()
	english.text = button.text
	add_child_autofree(english)
	assert_lt(english.get_minimum_size().x, button.get_minimum_size().x, "it is drawn so")
	assert_eq(english.atr(english.text), "Create Starter Level", "outside the domain")
	assert_eq(String(TranslationServer.translate("Create Starter Level")), "Create Starter Level")
	assert_eq(
		HFTranslationScript.t("Snap to Grid"), "Snap to Grid", "a word it lacks stays English"
	)
	assert_eq(HFTranslationScript.tn("{count} brush", "{count} brushes", 3), "{count} pinceles")
	assert_eq(HFTranslationScript.tn("{count} brush", "{count} brushes", 1), "{count} pincel")


func test_the_palette_shows_a_command_in_the_language_and_finds_it_by_either_name():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var palette = rig.plugin._hotkey_palette
	var entry: Dictionary = palette._entry_of("hollow")
	assert_eq(entry["shown"], "Ahuecar")
	assert_eq(entry["button"].atr(entry["button"].text), "Ahuecar", "the row shows it")
	assert_true(str(entry["button"].tooltip_text).begins_with("Ahuecar"))
	palette._on_search_changed("ahuecar")
	assert_eq(palette._shown[0]["action"], "hollow", "found by its name in the language")
	palette._on_search_changed("hollow")
	assert_eq(palette._shown[0]["action"], "hollow", "and by its English name")
	assert_eq(entry["button"].text, "Ahuecar (hollow)", "shown as what matched")
	var ran := []
	palette.action_invoked.connect(func(action): ran.append(action))
	entry["button"].pressed.emit()
	assert_eq(ran, ["hollow"], "the command id stays English")
	assert_eq(
		HFCommandRegistryScript.label("hollow"), "Hollow", "and so does what the bridge reads"
	)
	palette._on_search_changed("")


func test_every_catalog_keeps_the_placeholders_of_its_english():
	var folders := [HFTranslationScript.CATALOGS, SPANISH]
	var checked := 0
	for folder in folders:
		for file in DirAccess.get_files_at(folder):
			if not HFTranslationScript.EXTENSIONS.has(file.get_extension()):
				continue
			var path: String = folder.path_join(file)
			var problems := placeholder_problems(FileAccess.get_file_as_string(path))
			assert_eq(problems, PackedStringArray(), path)
			checked += 1
	assert_gt(checked, 0, "the test catalog at least")
	var broken := 'msgid "Removed {count} materials"\nmsgstr "Quitados {cuenta} materiales"\n'
	assert_eq(placeholder_problems(broken).size(), 1, "a renamed placeholder is caught")
	broken = 'msgid "%d of %s"\nmsgstr "%s de %d"\n'
	assert_eq(placeholder_problems(broken).size(), 1, "so are printf ones out of order")


func test_a_word_a_table_holds_for_a_control_is_found():
	var source := (
		"\n"
		. join(
			[
				"const FIELDS := [",
				'	{"key": "width", "label": "Width", "tooltip": "How wide it is"},',
				'	{"label": "Shown %s" % x, "help":',
				'	"On the next line"},',
				'	{"title": name, "blurb": ("Joined" + " here")},',
				"]",
				'var picked := spec["label"]',
				"match key:",
				'	"title":',
				"		pass",
			]
		)
	)
	var ids: Array = PotCatalog.script_words(source).map(func(word): return word[0])
	assert_eq(ids, ["Width", "How wide it is", "On the next line", "Joined here"])


func test_stopping_the_plugin_takes_its_catalogs_out():
	HFTranslationScript.load_catalogs()
	assert_true(TranslationServer.has_domain(HFTranslationScript.DOMAIN))
	HFTranslationScript.unload()
	assert_false(TranslationServer.has_domain(HFTranslationScript.DOMAIN))
	HFTranslationScript.load_catalogs()
	assert_eq(HFTranslationScript.t("Hollow"), "Ahuecar", "and starting it loads them again")


## Each message whose translation names a placeholder its English does not, or
## drops one, or puts printf ones in another order.
static func placeholder_problems(catalog: String) -> PackedStringArray:
	var named := RegEx.create_from_string(PLACEHOLDER)
	var printf := RegEx.create_from_string(PRINTF)
	var out := PackedStringArray()
	for entry in PotCatalog.read_po(catalog):
		var english: String = entry["id"]
		var plural: String = entry["plural"]
		var want_named := _found(named, english + " " + plural, true)
		var want_printf := _found(printf, english, false)
		for text in entry["strings"]:
			if text == "":
				continue
			var have_named := _found(named, text, true)
			var ok := have_named == want_named
			if plural != "":
				# A form for one may leave the number out.
				ok = have_named.all(func(name): return want_named.has(name))
			if not ok or _found(printf, text, false) != want_printf:
				out.append("%s: %s" % [english, text])
	return out


static func _found(re: RegEx, text: String, as_set: bool) -> Array:
	var out: Array = []
	for found in re.search_all(text):
		var value := found.get_string()
		if not (as_set and out.has(value)):
			out.append(value)
	if as_set:
		out.sort()
	return out
