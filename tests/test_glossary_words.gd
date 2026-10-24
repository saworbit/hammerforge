extends GutTest
## One name for each idea (#1657). `docs/glossary.md` lists, for each idea, the
## words not to use for it. No label, tooltip, toast or message in the addon, and
## no page of the docs, may use one, so a new tooltip cannot bring a synonym back.
## A failure names the file and the line.
##
## Addon strings are read as the string literals with a space in them, so a key
## or a code name such as `subtract_preview` is never taken for a word. The
## palette's search words, `aliases`, are synonyms on purpose. In the docs, code
## in backticks and fenced code are left out: a code name or an accepted bridge
## value such as `"subtract"` is written that way.

const GLOSSARY := "res://docs/glossary.md"
const ADDON_DIR := "res://addons/hammerforge/"
const DOC_DIR := "res://docs/"
const MORE_DOCS := ["res://README.md"]
## The glossary names the words, and the command reference is written from the
## registry, whose strings the addon check reads already.
const SKIP_DOCS := ["glossary.md", "commands.md"]
## Lines that may hold a synonym on purpose.
const ALLOWED_MARKS := ['"aliases"']


## The phrases every "Don't use" line of the glossary lists.
static func banned_words() -> PackedStringArray:
	var out := PackedStringArray()
	var text := FileAccess.get_file_as_string(GLOSSARY)
	for line in text.split("\n"):
		var at := line.find("**Don't use:**")
		if at < 0:
			continue
		for word in line.substr(at + "**Don't use:**".length()).split(","):
			var cleaned := word.strip_edges().trim_suffix(".").strip_edges()
			if cleaned != "" and not out.has(cleaned.to_lower()):
				out.append(cleaned.to_lower())
	return out


static func _matchers(words: PackedStringArray) -> Array:
	var out: Array = []
	for word in words:
		var pattern := "(?i)\\b%s(s|es)?\\b" % _escaped(word)
		out.append([word, RegEx.create_from_string(pattern)])
	return out


static func _escaped(word: String) -> String:
	var out := ""
	for ch in word:
		out += ("\\" + ch) if ch in ".^$*+?()[]{}|/\\" else ch
	return out


## The words to avoid that one line of GDScript's strings use.
static func offences_in_gd_line(line: String, matchers: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var stripped := line.strip_edges()
	if stripped.begins_with("#"):
		return out
	for mark in ALLOWED_MARKS:
		if line.contains(mark):
			return out
	var strings := RegEx.create_from_string('"(?:[^"\\\\]|\\\\.)*"')
	for found in strings.search_all(line):
		var literal := found.get_string()
		if not literal.contains(" "):
			continue
		for pair in matchers:
			if (pair[1] as RegEx).search(literal) != null and not out.has(pair[0]):
				out.append(pair[0])
	return out


## The words to avoid one line of a page uses, with its inline code taken out.
static func offences_in_doc_line(line: String, matchers: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var prose := RegEx.create_from_string("`[^`]*`").sub(line, "", true)
	for pair in matchers:
		if (pair[1] as RegEx).search(prose) != null and not out.has(pair[0]):
			out.append(pair[0])
	return out


func _gd_files(dir_path: String, out: PackedStringArray) -> PackedStringArray:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			out.append(dir_path + file_name)
	for sub in dir.get_directories():
		_gd_files(dir_path + sub + "/", out)
	return out


func _doc_files() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(DOC_DIR)
	if dir != null:
		for file_name in dir.get_files():
			if file_name.ends_with(".md") and not SKIP_DOCS.has(file_name):
				out.append(DOC_DIR + file_name)
	for path in MORE_DOCS:
		if FileAccess.file_exists(path):
			out.append(path)
	return out


func test_the_glossary_lists_words_to_avoid():
	var words := banned_words()
	assert_true(words.has("subtract preview"), "cut preview has its old name")
	assert_true(words.has("subtractive brush"), "and cut brush its old names")
	assert_true(words.has("generator"), "and structure the code's")


func test_a_tooltip_with_a_word_to_avoid_is_caught():
	var matchers := _matchers(banned_words())
	var line := '	button.tooltip_text = "Toggle the Subtract Preview"'
	assert_eq(offences_in_gd_line(line, matchers), PackedStringArray(["subtract preview"]))
	assert_eq(offences_in_gd_line('	var key := "subtract_preview"', matchers).size(), 0)
	assert_eq(
		offences_in_gd_line('		"aliases": ["negative brush", "cut"],', matchers).size(), 0
	)
	assert_eq(
		offences_in_doc_line("Every `subtractive brush` in code is fine.", matchers).size(), 0
	)


func test_no_label_tooltip_toast_or_message_uses_a_word_to_avoid():
	var matchers := _matchers(banned_words())
	var found: Array = []
	for path in _gd_files(ADDON_DIR, PackedStringArray()):
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			for word in offences_in_gd_line(lines[i], matchers):
				found.append('%s:%d uses "%s"' % [path, i + 1, word])
	assert_eq(found, [], "use the glossary's word")


func test_no_page_uses_a_word_to_avoid():
	var matchers := _matchers(banned_words())
	var found: Array = []
	for path in _doc_files():
		var fenced := false
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			if lines[i].strip_edges().begins_with("```"):
				fenced = not fenced
				continue
			if fenced:
				continue
			for word in offences_in_doc_line(lines[i], matchers):
				found.append('%s:%d uses "%s"' % [path, i + 1, word])
	assert_eq(found, [], "use the glossary's word")
