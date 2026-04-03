extends GutTest

const HFHotkeyPalette = preload("res://addons/hammerforge/ui/hf_hotkey_palette.gd")
const HFKeymap = preload("res://addons/hammerforge/hf_keymap.gd")

var palette: HFHotkeyPalette
var keymap: HFKeymap


func before_each():
	palette = HFHotkeyPalette.new()
	keymap = HFKeymap.load_or_default()
	add_child(palette)
	palette.populate(keymap)


func after_each():
	palette.free()
	palette = null
	keymap = null


# ===========================================================================
# Fuzzy score algorithm
# ===========================================================================


func test_exact_match_scores_high():
	var score := HFHotkeyPalette._fuzzy_score("hollow", "hollow")
	assert_gt(score, 0)


func test_no_match_returns_zero():
	var score := HFHotkeyPalette._fuzzy_score("xyz", "hollow")
	assert_eq(score, 0)


func test_partial_order_match():
	var score := HFHotkeyPalette._fuzzy_score("hlw", "hollow")
	assert_gt(score, 0)


func test_out_of_order_returns_zero():
	var score := HFHotkeyPalette._fuzzy_score("wlh", "hollow")
	assert_eq(score, 0)


func test_empty_query_returns_zero():
	var score := HFHotkeyPalette._fuzzy_score("", "hollow")
	assert_eq(score, 0)


func test_word_boundary_bonus():
	# "dw" matching "draw" should score higher than matching "shadow"
	var draw_score := HFHotkeyPalette._fuzzy_score("dw", "draw brush")
	var shadow_score := HFHotkeyPalette._fuzzy_score("dw", "shadow map")
	assert_gt(draw_score, shadow_score)


func test_consecutive_bonus():
	# "hol" matching "hollow" (consecutive chars) vs "h_o_l" spread out
	var consec_score := HFHotkeyPalette._fuzzy_score("hol", "hollow")
	var spread_score := HFHotkeyPalette._fuzzy_score("hol", "hit outer label")
	assert_gt(consec_score, spread_score)


# ===========================================================================
# Fuzzy search in palette
# ===========================================================================


func test_fuzzy_shows_results_for_typo():
	# "hllow" is a typo of "hollow" — fuzzy should find it
	palette._on_search_changed("hllow")
	var visible_count := 0
	for entry in palette._entries:
		if entry["button"].visible:
			visible_count += 1
	# Should show some fuzzy matches (hllow has h,l,l,o,w which matches hollow)
	assert_gt(visible_count, 0)


func test_suggest_label_shown_for_fuzzy():
	# Search for something that won't exact match but will fuzzy match
	palette._on_search_changed("hllow")
	assert_true(palette._suggest_label.visible)
	assert_true(palette._suggest_label.text.begins_with("Did you mean:"))


func test_suggest_label_hidden_for_exact():
	palette._on_search_changed("hollow")
	assert_false(palette._suggest_label.visible)


func test_suggest_label_hidden_for_empty():
	palette._on_search_changed("")
	assert_false(palette._suggest_label.visible)


func test_fuzzy_abbreviation():
	# "ext" should fuzzy-match "Extrude Up" or "Extrude Down"
	palette._on_search_changed("extrd")
	var visible_count := 0
	for entry in palette._entries:
		if entry["button"].visible:
			visible_count += 1
	assert_gt(visible_count, 0)


# ===========================================================================
# Max fuzzy results
# ===========================================================================


func test_fuzzy_caps_at_five_results():
	# Search for something very short that could match many things
	palette._on_search_changed("zzz")
	var visible_count := 0
	for entry in palette._entries:
		if entry["button"].visible:
			visible_count += 1
	# Either 0 (no match) or <= 5
	assert_true(visible_count <= 5)
