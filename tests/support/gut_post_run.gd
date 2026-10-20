extends GutHookScript
## After the last test: the run's folder goes, with whatever the tests left in it
## (#1304). `gut_pre_run.gd` says what the folder is for.

const GutPreRun = preload("res://tests/support/gut_pre_run.gd")


func run() -> void:
	GutPreRun.remove_folder(GutPreRun.folder())
