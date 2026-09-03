extends GutTest
## HFLog warning capture.
##
## `HFLog.warn()` is the project's `push_warning()` wrapper: tests suppress
## expected warnings with `begin_test_capture()` so negative-path coverage does
## not fill the suite output with noise.


func after_each():
	# Never leave a capture armed for the next test.
	HFLog.end_test_capture()


func test_warn_outside_a_capture_does_not_raise_an_engine_error():
	# Regression: _capture_warning() called Engine.get_meta(key, null), and
	# Object.get_meta() only honours a default that is not null — otherwise it
	# fails and returns Variant(). Outside a capture the key is absent, so every
	# warning in the running editor also printed "Method/function failed".
	HFLog.warn("HammerForge: test warning outside capture")
	assert_eq(HFLog.get_captured_warnings().size(), 0, "nothing is captured when idle")


func test_capture_collects_warnings():
	HFLog.begin_test_capture(["expected pattern"])
	HFLog.warn("HammerForge: expected pattern here")
	var captured := HFLog.get_captured_warnings()
	HFLog.end_test_capture()
	assert_eq(captured.size(), 1, "the warning was captured")
	assert_string_contains(str(captured[0]), "expected pattern", "the message is preserved")


func test_capture_collects_unsuppressed_warnings_too():
	# Suppression only silences the console; capture always records, so a test
	# can still assert on a warning it chose not to suppress.
	HFLog.begin_test_capture(["something else"])
	HFLog.warn("HammerForge: an unrelated warning")
	var captured := HFLog.get_captured_warnings()
	HFLog.end_test_capture()
	assert_eq(captured.size(), 1, "the warning was still recorded")


func test_end_capture_clears_the_buffer():
	HFLog.begin_test_capture(["noise"])
	HFLog.warn("HammerForge: noise")
	HFLog.end_test_capture()
	assert_eq(HFLog.get_captured_warnings().size(), 0, "the buffer is emptied")


func test_end_capture_is_safe_without_a_matching_begin():
	HFLog.end_test_capture()
	HFLog.end_test_capture()
	assert_eq(HFLog.get_captured_warnings().size(), 0, "ending an idle capture is a no-op")


func test_get_captured_warnings_returns_a_copy():
	HFLog.begin_test_capture(["noise"])
	HFLog.warn("HammerForge: noise one")
	var first := HFLog.get_captured_warnings()
	first.append("mutated by the caller")
	HFLog.warn("HammerForge: noise two")
	var second := HFLog.get_captured_warnings()
	HFLog.end_test_capture()
	assert_eq(second.size(), 2, "caller-side mutation did not reach the buffer")
