@tool
extends RefCounted
## How close a typed name is to a real one: the palette's fuzzy search, and the
## bridge's "did you mean" for a command id or a setting it does not know (#1651).


## A score above 0 when every letter of `query` appears in `target` in order,
## higher for a tighter match: letters side by side, or at the start of a word.
## 0 for no match.
static func fuzzy_score(query: String, target: String) -> int:
	if query.is_empty():
		return 0
	var qi := 0
	var score := 0
	var last_match_pos := -1
	for ti in range(target.length()):
		if qi < query.length() and target[ti] == query[qi]:
			# Bonus for consecutive matches
			if last_match_pos >= 0 and ti == last_match_pos + 1:
				score += 3
			# Bonus for matching at word boundary
			elif ti == 0 or target[ti - 1] == " " or target[ti - 1] == "_":
				score += 2
			else:
				score += 1
			last_match_pos = ti
			qi += 1
	if qi < query.length():
		return 0  # Not all query chars found
	return score


## The letters to add, drop, change or swap with the one beside it to turn `a`
## into `b`, so "widht" is 1 from "width".
static func edit_distance(a: String, b: String) -> int:
	var rows: Array = []
	for i in a.length() + 1:
		var row := PackedInt32Array()
		row.resize(b.length() + 1)
		row[0] = i
		rows.append(row)
	for j in b.length() + 1:
		rows[0][j] = j
	for i in range(1, a.length() + 1):
		for j in range(1, b.length() + 1):
			var cost := 0 if a[i - 1] == b[j - 1] else 1
			var best := mini(
				mini(rows[i - 1][j] + 1, rows[i][j - 1] + 1), rows[i - 1][j - 1] + cost
			)
			if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
				best = mini(best, rows[i - 2][j - 2] + 1)
			rows[i][j] = best
	return rows[a.length()][b.length()]


## Up to `most` keys of `names` nearest `query`, nearest first. Each key is
## matched by the words it lists, such as a command's id, label and aliases.
## Nothing when nothing is close, rather than a poor guess.
static func nearest(query: String, names: Dictionary, most: int = 3) -> PackedStringArray:
	var typed := _words(query)
	var scored: Array = []
	for key in names:
		var best := 0
		var distance := 1 << 20
		for word in names[key]:
			var name := _words(str(word))
			best = maxi(best, _closeness(typed, name))
			distance = mini(distance, edit_distance(typed, name))
		if best > 0:
			scored.append([best, distance, str(key)])
	scored.sort_custom(_nearer)
	var out := PackedStringArray()
	for item in scored.slice(0, most):
		out.append(item[2])
	return out


## Closer first, then fewer letters off, then by name.
static func _nearer(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] > b[0]
	if a[1] != b[1]:
		return a[1] < b[1]
	return a[2] < b[2]


## How near a typed name is to one name, both as `_words()` gives them: 0 for not
## near at all.
static func _closeness(typed: String, name: String) -> int:
	if typed.is_empty() or name.is_empty():
		return 0
	if typed == name:
		return 100
	# "hollow brush" holds Hollow's id, "make arch" an alias of Create Structure.
	if name.length() >= 3 and (" %s " % typed).contains(" %s " % name):
		return 80
	if typed.length() >= 3 and (" %s " % name).contains(" %s " % typed):
		return 70
	var distance := edit_distance(typed, name)
	if distance <= maxi(1, floori(typed.length() / 4.0)):
		return 60 - distance
	# "move floor" is Move to Floor with a word left out.
	if fuzzy_score(typed, name) > 0 and distance <= floori(typed.length() / 3.0):
		return 40
	return 0


## `text` lower case, its underscores as spaces and one space between words.
static func _words(text: String) -> String:
	return " ".join(text.to_lower().replace("_", " ").split(" ", false))
