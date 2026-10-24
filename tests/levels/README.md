# Levels saved by each release

One folder per HammerForge release, each holding a level that release's own
build saved, so that every CI run loads last release's files with this build
(#1640). The round trip and persistence checks read a file the same build just
wrote; only an old file can show a change that stops old files loading.

Each folder holds:

- `level.hflevel`: the reference map, rebuilt and saved by that release, with a
  cordon round it (and a second where the release keeps more than one);
- `level.tscn`: the scene with that level in it, as that release saved it;
- `expected.json`: what `level_census.gd` counted in it, with that release.

`reference_map/` holds the reference map a September build wrote, and no scene.
It was moved here from `addons/hammerforge/data/` when the map there was rebuilt
for #1815.

`tests/test_release_levels.gd` loads every folder's level, counts it again with
this build and compares, saves it again and checks the copy loads at this
build's format, and opens the scene. It also edits each one: a nudge undone and
redone, a placement undone with every brush from the file kept as the node it
was, a save after that undo, and Compare with File against its own file. A count a release changes on purpose goes
in that test's `KNOWN` list, with its reason and issue number.

## The one rule

**Never write a file here with a newer build.** A file's whole value is that an
old build wrote it. If a check needs something a level does not hold, add it to
the next release's level, not to an old one.

## Adding a release

After tagging a release, before the next one starts:

```bash
git worktree add --detach ../hf-release <tag>
cd ../hf-release
mkdir -p tests/levels
cp <this checkout>/tests/levels/level_census.gd <this checkout>/tests/levels/save_release_level.gd tests/levels/
godot --headless --import --path .
godot --headless -s res://tools/build_reference_map.gd --path .
godot --headless -s res://tests/levels/save_release_level.gd --path . -- --out=<this checkout>/tests/levels/<version>
```

Then commit the new folder. No code changes: the test finds every folder with
an `expected.json`.
