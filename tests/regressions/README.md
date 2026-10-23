# Shrunk chaos cases

Each `chaos_<seed>_<step>.json` here is a failing `chaos` run cut down to the
steps that matter, written by `tools/vibe/shrink_chaos.gd` (#1644).
`tests/test_chaos_regressions.gd` replays every one from a fresh level in each
GUT run and expects nothing to break.

While the bug a case shows is open, give it `"known": "#<issue>: <why>"`. The
test then holds it as pending, and fails once it passes, so the entry comes off
and the case guards the fix.
