extends GutHookScript
## After the last test: the run's folder goes, with whatever the tests left in it
## (#1304). `gut_pre_run.gd` says what the folder is for.
##
## And the run fails if the developer's own preferences file is not as the run
## found it (#1581). Here rather than in a test, because a hook runs once after
## every script a run collects: each CI shard, a `-gselect` subset, a whole local
## run. A test that sorts last is not last in a shard or a subset, and sees
## nothing the scripts after it do.

const GutPreRun = preload("res://tests/support/gut_pre_run.gd")
const RealPrefsGuard = preload("res://tests/support/real_prefs_guard.gd")


func run() -> void:
	GutPreRun.remove_folder(GutPreRun.folder())
	if GutPreRun.real_prefs_before == null:
		return
	var change := RealPrefsGuard.change_since(GutPreRun.real_prefs_before)
	if change == "":
		return
	var says := "The preferences file every checkout shares changed during this run: %s." % change
	gut.logger.error(says + " A test wrote it, or an editor open on the project saved it (#1581).")
	# Only ever 1: GUT takes this hook's code in place of its own, so setting 0
	# would pass a run whose tests failed.
	set_exit_code(1)
