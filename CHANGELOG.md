# Changelog

All notable changes to this project will be documented in this file.
The format is based on Keep a Changelog, and this project follows semantic versioning.

## [Unreleased]
### Fixed
- **The uid check says what it has not graded** (#804). It reads the list of
  files git tracks, and that is deliberate: a `.uid` sitting untracked beside a
  tracked script is the exact failure it exists to catch, and walking the disk
  would find that file and call the tree fine. The mirror case was invisible. A
  script written and not staged yet is in neither list, so the check passed,
  `python tools/run_local_checks.py` printed `19 passed, 0 failed`, and the
  first thing to notice the missing id was CI on the next push. That is what
  happened to the test file for #801, which kept its id only because someone
  went looking afterwards. Untracked sources are now listed under the verdict,
  the ones carrying no id are marked, and a line says they fail as soon as they
  are staged. It stays a pass, because a scratch file in a working copy is not
  a defect and failing on one would start refusing trees that are fine. The
  success line now names git as what it is speaking for, rather than reading
  like a statement about everything in front of you.
- **Bake Check reads the connector mode before it warns about stairs** (#802).
  The stairs check compared `bake_connector_stair_height` against the navmesh
  agent's climb and never looked at which connectors the level was going to
  build, so it was wrong in both directions. In *Ramp* mode, which is the
  default, `HFAutoConnector` builds no stairs at all and never reads the step
  height, and the check still said a chunkier step made a staircase nothing
  could climb. Meanwhile a staircase placed by hand with the connector tool
  bakes whether or not auto-connectors are on and carries its own step, and the
  check returned at its first line without measuring it. It now works out the
  connectors the bake would actually build, the same way the ramp half added in
  #798 does, and measures the stairs among them. It reports once with a count,
  the tallest step and the cell it starts from. Both checks share one pass over
  the painted cells rather than walking them twice.

### Added
- **The stairs half of the Bake Check has tests** (#801). The check that warns
  when connector stairs rise higher than the navmesh agent can climb had none,
  and one of its four lines is a boundary that has to stay exactly where it is.
  `bake_connector_stair_height` and `bake_navmesh_agent_max_climb` both default
  to 0.25, so a stock project sits on the limit and must not be warned about.
  Read as an off-by-one and tightened to `<`, that puts a warning on the Bake
  Check of every default project, and the suite stayed green either way. The
  boundary and every early return now have a test, each one written by breaking
  the guard it covers and watching it fail. The `<=` says in a comment why it is
  not a `<`, and the paragraph explaining the check has moved onto the function
  it describes rather than the two helpers above it.
- **Bake Check measures ramps against the agent's slope** (#798). It already
  said when connector stairs were taller than the navmesh agent could climb,
  and said nothing when a connector ramp was steeper than the same agent could
  walk. Stairs are the mode almost nobody uses: Ramp is the default, and Auto
  is a ramp below the stair threshold. A ramp's slope is not a setting, it is
  the height difference between two painted cells over one cell of run, so the
  check works out the connectors the bake would actually build, ramps and
  stairs, committed and auto-detected, and measures the ramps among them. At
  the default cell size and the default 45 degrees, that is any drop over about
  a metre. It reports once with a count and names the steepest and the cell it
  starts from, because a terrace a metre above its neighbour is one boundary
  per cell along its whole edge and none of them has a node to click through to
  until the bake makes one. This is the warning that explains the empty nav
  region #788 started reporting.
- **The nav bake says what it made** (#788). Turning **Navmesh** on and baking
  produced a `BakedNavmesh` region and said nothing about it. Both of the ways
  that region can come out empty are silent in the engine: nothing reaches the
  parse at all, or geometry reaches it and no polygon survives the agent size.
  Either way the level exported, Test Level launched, and the first sign of
  trouble was an agent that would not move. Every nav bake now writes one line
  to the Console naming the parse source and the polygon count, and an empty
  region is a warning that says which of the two happened, which is also which
  fix it wants: collision to walk on, or an agent that fits what is there. The
  source is read back off the navmesh rather than assumed, because the property
  holding it was renamed between Godot versions and the setter can fall through
  to Godot's default without saying so.
- **Nothing let a script be committed without its id** (#783). Godot 4.4 and
  later keep a script's stable id in a `.uid` file beside it, because a `.gd`
  and a `.gdshader` are plain text with nowhere of their own to put one, while
  a `.tscn` writes it into its own header. When the `.uid` is missing Godot
  writes a fresh one on the next import, separately on each machine, so the
  file turns up untracked in whoever imported last and two people can commit
  different values for something that was meant to be stable. That already
  happened here: `tests/test_scoped_undo_step.gd` landed in #760 without its
  id and was not committed until #770, ten pull requests later, and then only
  because cutting a release ran an import on a machine that regenerated it. For
  that whole window the repository had one more test script than it had ids and
  nothing said so. `tools/check_uid_parity.py` now fails on a source with no id
  and on an id whose source is gone, across everything git tracks except the
  vendored addons, which are somebody else's to keep tidy.
- **The Asset Library check reads the version it was only printing** (#790).
  The entry carries two fields that have to agree, the commit it serves and the
  version it calls that commit, and they are typed into the same web form
  separately. The check compared the commit and printed the version as
  decoration, so `0.9.9` would have read as green. That matters because the
  version is the number a person reads before deciding whether to update: the
  download would be right and the page would advertise something else. It now
  compares against `version=` in `plugin.cfg` on the release branch, which is
  the literal source rather than the commit subject that happens to carry it,
  and reports it as `mislabelled` rather than as staleness, because nothing is
  stale and the fix is the other field. It fails rather than warns, since
  unlike a moderation queue this is entirely within a maintainer's power to
  fix today. A version correction already sitting in the queue is read the same
  way a queued commit paste is, so the check does not ask for it twice.
- **Something notices when the Asset Library entry goes stale** (#778). The last
  step of a release is a commit hash pasted into a web form by hand, and nothing
  looked at whether it had happened. `release.yml` prints the hash to its job
  summary, which is read once in the minutes after a release and never again, so
  a forgotten paste stayed invisible: the entry looks fine, the download works,
  and it quietly hands out an old plugin. A new weekly workflow compares the
  entry's `download_commit` against the head of `release` and fails once they
  have disagreed for more than three days. The grace period is the point. At the
  moment a release is cut they correctly disagree, and going red for that would
  be the kind of red that teaches people to ignore red.
  Comparing those two alone turned out not to be enough. An Asset Library edit
  does not take effect when it is submitted; it waits in a moderation queue. So
  there is a window where the paste has happened and the entry still serves the
  old commit, and a check that could not tell those apart would have said the
  paste was forgotten and asked for it again, which only adds a second record to
  the queue. That was the live state while this was being written: 0.3.2's paste
  was submitted 27 minutes after the release and was still queued. The check now
  reads the pending edits too, and a rejected one fails with the reason it was
  rejected.
  `release.yml` also carried the claim that the Asset Library has no API for
  updating an entry. It has one. The reason to keep pasting by hand is that its
  token comes from a username and password, and the edit is moderated either
  way, so automating it would put the account password in Actions secrets and
  still not remove the human. Corrected in place rather than left to be looked
  up a third time.
- **The plugin folder explains itself** (#780). `addons/hammerforge/` had 108
  entries at its top level and no README, so nothing in it said what it was, how
  to turn it on, or what not to do with it. That was survivable while the only
  download carried a README at its root, and stopped being survivable in 0.3.2:
  the addon-only zip added in #777 is `addons/` and nothing else, and the Asset
  Library install is `addons/` and `LICENSE`. Both of the routes most people take
  handed over a folder of `.gd` files with no explanation at all.
  `addons/hammerforge/README.md` is committed rather than generated at build
  time, so it is there when browsing the repository too, and it needs no build
  change: `SHIP` in `tools/build_release_tree.py` takes whatever git tracks under
  `addons/hammerforge`. It covers enabling the plugin, a first level, what the
  plugin writes into your project, and the one thing that bites on upgrade, which
  is that replacing the folder deletes anything you put inside it.

- **Where to get HammerForge** (#779). The release notes template named "the zip"
  when there are two, with near-identical names and the bigger one sorting first,
  and told people to point the Asset Library at the `release` branch, which is not
  a thing that can be done: the entry takes a commit hash, pasted by hand, and a
  user never touches it. 0.3.2's notes read correctly only because they were
  written by hand; the next release drafted by the bot would have carried the
  wrong text again. `.github/release-drafter.yml` now names both archives, says
  which one most people want, and gives the AssetLib route instead of the branch
  one. `docs/HammerForge_Install_Upgrade.md` gained the same answer, because its
  first install step was "copy `addons/hammerforge` into your project" and nothing
  in the repository said where to copy it from.
- **One command runs what CI will fail you on** (#792). CI's two lint jobs run
  twenty-odd commands. DEVELOPMENT.md listed four of them and CONTRIBUTING.md
  listed three, both kept by hand, so you could run every line either page gave
  you and still go red on `check_project_settings.py`, `check_dead_declarations.py`
  or `ruff` -- under a check named after GDScript formatting. `tools/run_local_checks.py`
  runs them all instead, and names the four it cannot run here with the reason.
  `--check` reads `ci.yml` and fails in CI when a step stops being accounted for,
  so a guard added to CI now forces a decision about what happens locally rather
  than leaving one to be noticed a release later. Both pages point at the runner
  and no longer carry a copy of the list.

### Fixed
- **The project-settings guard gives the same answer as CI** (#795).
  DEVELOPMENT.md asks you to run `git update-index --skip-worktree
  project.godot` so an editor bridge you enable locally stays out of
  `git status`. Doing that and enabling anything then failed
  `tools/check_project_settings.py` on your machine from then on, because it
  read the copy on your disk while CI reads the committed one. The same command
  disagreed with itself depending on where it ran. That was survivable while it
  was a command you ran by hand, and stopped being survivable in #794, which
  put it inside the one runner both DEVELOPMENT.md and CONTRIBUTING.md now tell
  you to run before pushing: a runner that is permanently one-red for everyone
  following the other half of the same page is a runner people stop reading.
  The guard now reads the committed blob whenever git has been told to stop
  watching the file, by either `--skip-worktree` or `--assume-unchanged`, and
  the copy on disk in every other case, which is still the one heading for a
  commit and still the case #277 was about. An enable that really is committed
  fails either way. The runner's note explaining the wrong answer is gone,
  because after this it would be telling you to ignore a failure CI is about to
  repeat. `--selftest` now builds a throwaway repository and moves the flag
  around it, since the old cases handed strings to the checker and could not
  see which copy a run had picked up.

### Documentation
- **ROADMAP said no issues were open while issues were open** (#799). The test
  and script counts either side of that claim are rewritten by
  `tools/update_test_counts.py` on every green run. The claim sitting between
  them was hand written and nothing touched it, so the sentence refreshed often
  enough to look current while the one part of it that was a statement about
  the project rather than a measurement went unchecked. A tracker that changes
  weekly does not belong in a roadmap, so it is gone. The rest of the sentence
  stays: every known limitation is still either covered by tests or written
  down beside the wave that introduced it.
- **Stair Threshold's documented default was the old one.** The User Guide said
  32.0. The control and the property have both been 2.0 since the world scale
  changed in #625, and 32 was a Quake-scale number no level reaches. Reading
  the old figure is what makes Auto look like it is always a ramp.
- **A cold `.godot` cache invents parse errors** (#784). The first editor launch
  after an import reports reimport noise and `Cyclic reference` against scripts
  in `tests/`, naming real files, and the same tree comes up clean on the next
  launch. It cost an hour during 0.3.2 and two clean worktrees to confirm that
  nothing was wrong. DEVELOPMENT.md now says to confirm any parse error
  headlessly first, with the `-gselect=test_suite_integrity` run that answers it.
- **Why the first CI job is called what it is** (#793). `GDScript Lint & Format`
  also runs the four checks over the tree, so a missing `.gd.uid` fails a check
  whose name says formatting. The name is what the branch ruleset requires, and
  the ruleset is not in this repository, so renaming the job alone would leave
  every open pull request waiting on a check that never reports. DEVELOPMENT.md
  records that, rather than leaving the next reader to work it out.

## [0.3.2] - 2026-09-19
### Fixed
- **Test Level starts a level with a player in it again** (#771). It bakes,
  validates the spawn and launches, and the window that came up was flat grey:
  no player, and so no camera. That is the loop the documentation leads with.
  `_start_playtest()` is the only thing that builds a `PlaytestPlayer`, and it
  was gated behind `auto_spawn_player`, whose default #719 flipped from `true`
  to `false` -- after 0.3.0 shipped, and three days after the last run of the
  release gate, which is why nothing caught it until this one.
  #719 was right about its own bug: a mapper's own game scene with a `LevelRoot`
  in it should not get a second character controller. The two cases are
  genuinely indistinguishable from inside the level, because Test Level plays
  the same scene the mapper would play themselves -- so the launcher now says
  which it is. Every way the dock starts a playtest goes through
  `HFDockManageHandler.launch_playtest()`, which leaves a stamped request at
  `res://.hammerforge/playtest.request`, and the run collects it in `_ready()`.
  Under a dot directory, which an export does not ship. The request is removed
  by the first run after it whatever that run decides, so one that nobody
  collected -- a refused bake, an editor that went away -- expires rather than
  turning the mapper's next ordinary F5 into a playtest; and one older than ten
  minutes is not a request at all.
  Written to a file rather than set on the node because `play_current_scene()`
  plays the scene *file*: a property set on the live node would have to be saved
  into the mapper's own scene to reach the running instance, and would then be
  on for their shipped game too.
  Not caught by the suite or by the vibe scenarios because every one of them
  sets `auto_spawn_player` itself before `add_child()`, so none went through the
  path the button takes. The new coverage goes through `launch_playtest()`.

- **Redo of Create Starter Level brings the player spawn back** (#772). Undoing
  it twice takes the contents and then the `LevelRoot`; redoing put the node
  back and ran `create_new_level()` on it again, but `_ready()` does not run a
  second time, so the node returned without any of the children `_ready()` had
  given it. The floor and the sun came back regardless, because those are
  get-or-create against the root. The spawn did not, because it needs the
  entities container, and that reference was dangling. The `_setup_*` calls are
  now `_ensure_child_nodes()`, which `_ready()` and `create_new_level()` both
  run; each one was already get-or-create, so running it again is free.
  Rebuilding them was only half of it. Taking the `LevelRoot` out of the tree and
  putting it back also clears the owner of everything beneath it, and each
  `_setup_*` assigned an owner only on the branch that *creates* a node -- so a
  container that survived stayed unowned, which meant it was missing from the
  Scene dock and, worse, from the `.tscn` the next save wrote. Saving after an
  undo and a redo produced a 3.6 KB scene with no brushes and no spawn in it;
  it now produces the same 28 KB scene an untouched level does.
  `_reassert_container_owners()` goes through `_assign_owner()` rather than
  setting `owner` directly, so the nodes that are meant to have none -- a level's
  sources under `BAKE_ONLY` -- still get none.

- **The Bake row says how long the bake took, and is coloured** (#773). The
  release gate asks for both and the build did neither: the message was the
  literal `"Bake complete"`, and `_set_status(msg, false, ...)` *removes* the
  colour override rather than setting one, so a finished bake read as ordinary
  body text. There is now a `_set_status_success()` beside the warning and error
  ones, and the row reads `Bake complete in 340 ms`. The duration is formatted by
  `format_duration_ms()`, extracted from the estimate label so the guess before a
  bake and the report after it cannot drift into two formats. A bake whose start
  this dock did not see is reported without a duration rather than with one
  measured from zero.

- **A new level no longer arrives with a warning on it** (#774).
  `Generated/RegionOverlay` is a `MeshInstance3D` that has nothing to draw until
  a region is painted, and Godot warns about a mesh instance with no mesh -- so
  every level ever created carried a yellow triangle in the Scene dock and sat
  at one warning from the moment it existed. It gets an empty `ArrayMesh`, which
  satisfies the editor and renders nothing. Applied outside the create branch, so
  a level saved before this stops warning as soon as it is opened.
### Added
- **`tools/wait_for_ci.py` takes a commit as well as a pull request** (#763).
  The internals were always keyed to a commit; only the argument parser insisted
  on a pull request number. That left out the one commit most worth checking:
  after a squash merge, what landed on `main` has no pull request of its own, so
  there was no way to ask this tool whether the merge went green.
  `python tools/wait_for_ci.py 1b1e341` now answers. A commit resolves to itself
  every poll, so the head-moved handling that exists for CI's counts commit
  simply never fires, and the log drops the `#N` prefix rather than putting a
  pull request number on a commit that has none. A pull request number behaves
  exactly as before.
  Short SHAs are expanded through GitHub before they are used, because
  `gh run list --commit` matches nothing on an abbreviated one and answers with
  an empty list -- which this tool reads as "no run yet" and would have waited
  out the full forty-five minute timeout on. A SHA that is not a commit here now
  fails in about a second instead. An uppercase SHA is lowered for the same
  reason: run comparison is exact.

- **A reference map ships with the plugin** (#710). The five examples in
  `example_levels.json` each demonstrate one feature, and that file's schema
  carries brush shape, position, size and operation plus point entities. It
  cannot express a material, a UV, a tie, a wire, a visgroup, a navmesh or an
  occluder, so none of the examples was a level with those in it at once.
  `addons/hammerforge/data/reference_map.hflevel` is: two hollowed halls with the
  corridor's mouth cut through the inner wall of each, 119 brushes, 15 materials,
  216 faces with UVs anchored to world space so the texture runs through a floor
  to wall join, a visgroup per wing, three tied brush entities wired button to
  relay to door, a spawn the validator approves, and the bake options a shipped
  level uses. It is the first `.hflevel` in the repo.
  Rebuild it with `tools/build_reference_map.gd`, which is committed so the map
  is a reviewable script rather than an opaque blob.
  The new `reference-map` vibe scenario loads the committed file and takes it
  through validate, invariants, bake and export. That the file is committed is
  the point: `round-trip` and `persistence` both read a level the same build just
  wrote, so neither would notice a format change that stops last release's file
  from loading. This one would. It found the occluder bug below on its first run.

- **A cut's interior takes the cutter's texturing** (#746). Cutting a window left
  the reveal untextured and there was no way to fix it: those four faces do not
  exist until the boolean runs, so no panel in the editor can select one. The
  cutting brush is the only handle there is, and the engine already agrees —
  Godot's CSG gives a carved face the material of the face that cut it, which is
  also how the Quake-family editors this lineage comes from behave. A cutter now
  goes into the boolean as a mesh with one surface per material, the same way a
  solid has since #693, so the reveal wears what the cutter was painted with,
  face by face. A sill can differ from the jambs because they are different faces
  of the cutter. A cutter with one whole-brush material instead of painted faces
  stays on its exact prefab primitive and carries that material through.
  An untextured cutter leaves the interior bare, which is what it has always
  done. The friendlier-sounding alternative — inheriting the material of the wall
  it cut — is not well defined, because one cutter can cross several brushes
  wearing different materials, and the boolean offers nowhere to express it. What
  it must never inherit is the editor's translucent red subtract cue, and a test
  pins that.
  A mirrored cutter is the exception and stays on its primitive. A negative
  determinant inverts face winding, and the boolean reads an inverted mesh
  operand differently from the primitive it regenerates from `size`: on one wall
  and one cutter, 25.5000 against 25.6792. Painting a brush must not move where it
  cuts, so a mirrored one takes the exact path. #749, below, then stopped a brush
  reaching a bake mirrored at all, which leaves that guard as a backstop rather
  than a path anything travels.
- **Where friction and bounce come from, written down** (#744). A baked surface
  has Godot's default friction and bounce, nothing in the plugin sets
  `physics_material_override`, and nothing said so - so the natural assumption
  after texturing a floor `ice` was that something had happened. Shipping a Level
  now says plainly that it has not, and says where the tuning goes instead. That
  is the decision as much as the documentation: a `PhysicsMaterial` belongs to a
  body and a level has one body with a dozen materials, so friction cannot fall
  out of the texturing, and a mapper reaching for a texture called `ice` is
  choosing how a floor looks rather than asking for the physics of ice. So the
  naming is the plugin's job and the tuning is the game's. Two ways to do it are
  written up: a controller reading the surface name through `HFSurface` and
  applying its own numbers, which works on any bake and is what most levels want,
  or `bake_collision_mode` 2, which builds one `StaticBody3D` per visgroup that
  `physics_material_override` can go on when the engine has to resolve the
  friction itself. They do not combine, and the page says why.
- **A hit can name the surface it hit** (#707). Texturing a level is how a
  shipped game knows what is underfoot: the footstep sound, the impact decal, the
  bullet spark are all the same lookup against the surface a ray just touched.
  None of it reached the baked collision, which was one `StaticBody3D` with no
  metadata at all. The baked mesh had kept the materials as separate surfaces the
  whole time; the collision kept nothing. The bake now gives each material surface
  its own collision shape and writes the surface names onto the body, so the
  `shape` index a hit reports names the material that was hit. `HFSurface` does
  the lookup in one call, from a ray query result, from a `RayCast3D`, or from a
  body and an index. `names_on()` lists every name on a body, which is how a game
  checks its footstep table covers the level rather than finding the gap the first
  time somebody walks on the roof. The shape index rather than the triangle
  because the documented answer is not available: `face_index` is `-1` here from
  both `intersect_ray()` and `RayCast3D.get_collision_face_index()`, since this
  project runs Jolt, and a test pins that so a Godot release which starts
  populating it fails rather than the better route going unnoticed. The per-brush
  collision modes carry no names on purpose, because there a shape is a brush and
  a brush has six faces with six materials, and naming one of the six would be
  worse than saying nothing. Friction and bounce are still Godot's defaults for
  every surface; that half is #744.

### Removed
- **The `Use MultiMesh` bake toggle** (#692). It could not consolidate anything a
  bake produces, at any level size, in any arrangement. The report blamed the
  grouping key, which is object identity of the `Mesh` and is indeed never shared
  between two brushes. Fixing the key would have changed nothing: by the time
  consolidation ran there was only one `MeshInstance3D` in the container, because
  the structural pass merges every face into one mesh per material first, and one
  node cannot form a group of two whatever the key is. Three other paths were
  checked for somewhere it could fire. Props are instantiated into the exported
  scene rather than the baked container, so it never sees them; chunked bakes and
  visgroup layers do produce several mesh instances, but each holds distinct
  content, so identity keying gives groups of one again. The toggle cost a bake to
  discover and `bake-options` had already recorded that it produced byte-identical
  output without knowing why. The stated reason for wanting it was draw calls, and
  that is backwards: the merge already gives one draw call per material, which is
  the floor, and pulling the crates back out would give two. What multimesh buys
  on brushes is vertex memory. Where it would genuinely pay is repeated props,
  which are never merged and which do share a `Mesh` resource, and that is filed
  as #742 with the measurement and the reason it is a design decision rather than
  a rewiring: a prop is packed as a scene instance, so collapsing it discards its
  collision, its scripts and every child it had.

### Fixed
- **An undo scope handed to `restore_state()` is refused instead of read as a
  level** (#768). A scope is the brushes one action touched. A level state is the
  twenty-five keys `capture_state()` writes. Both have a `brushes` list in them,
  so a scope passed every check and was then read as a level that had nothing in
  it: every brush the scope did not name freed, the entities cleared, and the
  visgroups, groups, generators, duplicators, hollows and prefab instances all
  restored from nothing. The palette survived, because that is the one thing
  `restore_state()` only touches when the state carries it.
  An entity scope was already refused, but by accident. It keys its records by
  node path, which makes `entities` a set where a level state's is a list, and
  the shape check turned it away. A brush-only scope had no equivalent tell, so
  the safety was a property of a record shape rather than a decision.
  `capture_brush_scope()` now puts `HFValidation.UNDO_SCOPE_KEY` on what it
  returns, and `level_state_problem()` refuses any dictionary carrying that key
  on presence alone. The sites that keep a pre-state still pick the restore by
  hand, and that is still theirs to get right, but getting it wrong this way now
  costs the step and says so rather than costing the level in silence.
  A scope an editor session captured before this change carries no key, and
  `restore_brush_scope()` reads it exactly as it did: it takes the records and
  ignores everything else, so a live undo history keeps working across the
  reload.
  The comment at `plugin_paint_input.gd` that described the trap was wrong in
  both directions -- it said the materials were cleared, which they were not,
  and it did not mention the brushes outside the scope, which were deleted. It
  and the matching notes in `undo_helper.gd`, `hf_entity_system.gd` and
  `DEVELOPMENT.md` now say what happens.

- **Nudging, rotating or flipping an entity records that entity, not the level**
  (#761). The last of the undo sites that could name what they change. A
  selection with an entity in it, and a selection of nothing but entities, both
  took a whole-level snapshot per keypress, which the issue measured at 23.4 ms
  and 705 KB at 400 brushes, against 0.06 ms and 3.6 KB for the scoped step the
  same command already took on brushes alone. Arrow keys are held down, so it was
  the seam the issue said it was: the same keypress fast or slow depending on
  what else was selected.
  A scope now carries its entities beside its brushes, keyed by the node path
  the commands already name them by, and `apply_entity_record()` writes the
  record back onto the live node. That is what the issue parked this on: a
  restore that *rebuilds* an entity changes its node path, which is true of
  `restore_state()` and of nothing a scope does. Nudge, rotate and flip write
  `global_transform` and the `angle` property onto entities that are already
  there, so a scoped undo frees nothing and no path moves.
  The node name is written back only when no sibling holds it. Godot renames a
  node given a name one of its siblings has, so an unguarded write would move
  the very path the rest of the step looks its entities up by.
  `plugin_edit_actions.brush_scope()` is gone rather than widened. It existed to
  refuse a selection with an entity in it, and the only rule left is "at least
  one object", which every one of the four commands has already checked by the
  time it commits.

- **The UV spinboxes and a material dropped on a face record one brush, not the
  level** (#761). The last two undo sites that could name the brush they change
  and did not. Both edit one face of a brush that is already there: the spinboxes
  write the UV fields, the drop writes the slot index, and each rebuilds that one
  brush's preview. The spinbox path is dragged, so it was taking a whole-level
  snapshot per tick of a drag.
  The palette was the question worth asking of the drop rather than assuming,
  the same one a brush paint was asked in #762. A face material is a slot index
  rather than a material, so a slot the palette has no room for could plausibly
  have grown one. It does not: that index is refused and nothing is written.
  `tests/test_scoped_undo_step.gd` pins both, and pins the refusal beside them so
  the two are each other's control.

- **A material dropped on a brush that had no id did nothing** (#761). Brush ids
  are minted lazily, and a brush the floor painter built or one authored in the
  scene tree has not been through the mint, so its id is still empty. Seven
  places in the dock and the gizmo plugin handle that by asking
  `get_brush_info_from_node()` for an id, which mints one and writes it back. The
  material drop was the one site that invented its own fallback instead, the
  node's instance id, and nothing resolves that:
  `assign_material_to_faces_by_id()` looks brushes up by id only, so it found no
  brush and returned while the drop still reported success with a toast. The
  instance id could not have survived an undo either, because a rebuilt brush
  gets a new one and the redo would have aimed at a freed node. The drop asks for
  the mint now, like the other seven.

- **Bevel, inset and a resize record the brushes they change, not the level**
  (#761). Two more of the hand-rolled undo pairs are gone. An inset shrinks one face of one
  brush, which is the shape `dock._try_undoable_action()` already takes, so that
  site is now a call to it rather than a snapshot pair of its own. A bevel is a
  batch over the selected edges, so it keeps its own capture but scopes it to the
  brushes those edges belong to. Every brush in the selection is recorded, not
  only the ones a bevel succeeded on: an unchanged brush costs one record, and
  one left out would not come back.
  Both were measured before they were scoped rather than assumed: run between two
  whole-level captures, `brushes` is the only key either changes, and a scoped
  restore puts the level back to the dictionary it was. `tests/test_scoped_undo_step.gd`
  now pins both, and a bevel finds its edge at run time rather than hard-coding a
  pair, so a command that silently stopped doing anything fails the test instead
  of passing it.
  Deciding whether ids can be a scope is now `HFUndoHelper.capture_scope_or_state()`,
  which returns the state and the ids that restore it as one answer. They have to
  agree: a caller that asked for a scope, got the whole-level fallback and still
  passed its ids would register a 25-key level state to be put back through
  `restore_brush_scope()`. The sculpt path's own copy of that decision now calls
  the shared one.
  Beveling an edge that named the same vertex twice used to return true and add
  four degenerate faces, because every face meeting that corner counted as
  sharing the edge and the chamfer was then built along a zero-length direction.
  It is refused. The edge selection cannot produce one, but `bevel_edge()` is
  reachable from a custom tool.

  The gizmo resize drag scopes to the brush whose handle was pulled. It is held
  down, the way the sculpt stroke is, and it was still taking a whole-level
  snapshot per drag. Texture lock defers its UV work to the commit, so whether a
  resize writes outside the brush was a real question rather than a formality:
  a UV lives on the brush's own faces, and the pinning test says so.

- **Every displacement edit records the brush it edits, not the level** (#761).
  #737 gave four commands an undo step the size of the change and left the rest
  recording the whole level. The displacement commands were the biggest group
  still out there, and the sculpt drag was the worst of them: a stroke took a
  whole-level snapshot on mouse-down and another on mouse-up, 39 ms and 2.2 MB
  each, on a gesture a mapper holds down. It sculpts one face of one brush.
  Create, destroy, set power, elevation, smooth, noise, sew group and the sculpt
  drag itself now all record that brush. So does painting a material onto a
  brush: the paint writes `material_override` on the node and never reaches the
  palette, not even for a material no slot holds, which was the open question
  that had kept it unscoped.
  Sewing is the one displacement command that keeps the whole snapshot. It
  matches every displacement in the level to its neighbours by sew group, so it
  changes brushes the caller never named and cannot claim a brush scope.
  `tests/test_scoped_undo_step.gd` runs each of these commands between two
  whole-level captures and asserts `brushes` is the only key that differs, which
  is what the claim rests on. A command that grows a registry write fails there.

- **An undo step is the size of the change, not the size of the level** (#737).
  Every action recorded a whole-level snapshot. On a 900-brush map that was 39 ms
  before the brush moved, 51 ms to take back, and 2.2 MB held for the rest of the
  session, on an action that moved one brush -- and 24 of the snapshot's 25 keys
  were unchanged by it. The number of undo steps is the editor's scene history
  and not ours to cap, so the size of one is the only lever there is.
  A command that can say which brushes it changes, and that it changes nothing
  else, now records only those. Arrow-key nudge, rotate, flip and reset rotation
  can say it. At 400 brushes one of those steps is 0.06 ms to take, 0.45 ms to
  take back and 3.6 KB, against 23.4 ms, 28.1 ms and 705 KB before.
  A scoped undo does no clearing and no reconciling: it looks each brush up by
  id, and writes the transform and faces straight onto the node when that is all
  that differs, so the brush you nudged is still the brush you had selected. A
  record that differs in anything else -- a shape, a size, an operation -- goes
  back through `create_brush_from_info()`, the door every other restore uses, and
  is put back at the index it was captured at.
  Everything else is unchanged. A structural command, a mixed brush-and-entity
  selection, and every command that does not claim a scope all take the whole
  snapshot exactly as before.

- **A restored brush no longer pushes the brush id counter up** (#737).
  `create_brush_from_info()` read its id as `info.get("brush_id", _next_brush_id())`
  and GDScript evaluates that default whether the key is there or not, so every
  brush a restore put back minted an id it threw away. Loading a level left the
  counter hundreds higher than the level it had just built.

- **Four more bake settings travel with the level** (#755). Walking every
  exported property against what the `.hflevel` records turned up fourteen the
  file never wrote. Four of them change what a bake produces and their siblings
  were already in the file: `bake_navmesh_agent_max_climb`,
  `bake_navmesh_agent_max_slope`, `bake_connector_stair_threshold` and
  `bake_wire_io`. A level saved with wire I/O off reopened with it on and baked
  a dispatcher back in, which is the same surprise the occluders were. All four
  already had the bounded setters #373 gave their siblings, so a poisoned value
  out of a file is clamped on the way in rather than assigned. A file written
  before this carries none of the four keys and keeps whatever the level
  already had, rather than being reset by an absent key.

  The other nine stay out, and `capture_hflevel_settings()` now says why in
  place so the next walk of `get_property_list()` does not have to decide it
  again. Autosave on/off and its interval stay out because opening a level is
  not a way to switch off the mapper's autosave. The autosave path, the entity
  definitions path, the grid's colour, plane size and major line frequency, and
  the default brush size are editor or project scope rather than level data.
  `hflevel_compress` says how the file was written, which the file's own header
  already records. `cordon_aabb` was on the list and was never missing: it goes
  out flattened, as `cordon_aabb_pos` and `cordon_aabb_size`.

  Fixed while in there: importing a settings file whose
  `connector_stair_threshold` is not a number put 32 in the dock rather than the
  2 the property defaults to. Every other fallback in that block already matched
  its property, and 32 is a pre-#625 number.

- **The `docs-truth` scenario no longer reports a `.map` measurement as our own
  scale** (#754). The detector had two categories for a measurement of sixteen
  units or more: current HammerForge scale, which it flags, and a line the guide
  explains as history, which it excuses. A measurement in another format's own
  units is neither. A `.map` file is Quake scale by definition, so "a 12-metre
  room exports as 384 units" is the right number to print and it will never
  change. That correct line was flagged on every run, which is how a real
  finding gets ignored. There is now a third category for another format's
  units, checked before the historical one, so the line about a 112 unit
  corridor is not counted as a change we once made either.

- **A level saved with occluders on now bakes with them on when it is reopened**
  (#710). `bake_generate_occluders` and `bake_occluder_min_area` were exported
  level properties that the `.hflevel` never wrote and never read, so the setting
  reverted to off on load and the next bake produced no occluders. Nothing
  reported it, and occluders only change frame time, so the loss stayed invisible
  until somebody profiled. Both settings now travel with the level. A file
  written before this has neither key and keeps whatever the level already had,
  rather than being switched off by an absent key. `bake_occluder_min_area` also
  gained the bounded setter its siblings got in #373 - it escaped that sweep by
  not being in the file at the time, and a minimum area of zero or less would
  make an occluder of every face group in the level.

- **A corrupt palette no longer raises a script error on the way back in**
  (#752). `restore_state()` has a guard for a saved palette whose slots hold
  something that is not a Material: `set_materials()` keeps such a slot empty and
  names it. The fast path put in front of that guard by #705, which skips
  repainting every brush when the palette is not part of what changed, compared
  the two arrays with `!=` - and in GDScript `!=` between an Object and an int is
  a runtime error rather than a false. The comparison now asks each slot's type
  first, so a slot of a different type answers "not the same palette" instead of
  throwing. A save produces a typed array and cannot hold junk, but a state does
  not have to come from a save: `.hflevel` is JSON, an undo snapshot is built
  from the same shape, and a file written by an older version or edited by hand
  can put anything in that array.
  What it did is narrower than it looked. The error unwinds only
  `palette_matches()`, and a function typed `-> bool` that unwinds returns false,
  so `set_materials()` ran anyway and the level still came back. What it cost was
  a red error in the Debugger for a file the plugin was already written to
  survive, and `tools/vibe/scenarios/persistence.gd` reporting a script error
  instead of the answer it was asking for. That scenario now runs clean.
  The rest of the restore path was checked for the same shape and does not have
  it. It compares through `str()`, through `is`, or through `recursive_equal()`,
  and all three are defined for any pair of types.
- **A mirrored brush no longer bakes inside out, and a mirrored cutter cuts**
  (#749). Nothing in the editor calls this mirroring. It is `scale` with a
  negative component, which Godot's own gizmo will do to a brush if a handle is
  dragged past zero, and which the Inspector will take as a typed number. The
  basis then has a negative determinant, which inverts the winding of every face
  built through it: measured on one 2 x 2 x 2 brush, all twelve triangles came out
  the other way round. The viewport draws the brush the right shape either way, so
  the bake was the first place it showed, and on a cutter it showed as a window
  that did not open - the wall and cutter that should have left 21.75 left 26.25,
  which is the wall plus the cutter. It was not cutting less. It was being added.
  HammerForge's own Flip has never had this problem, because it folds its
  reflection back through a local axis so the basis stays right-handed. That same
  fold is now applied to a mirror that arrived from anywhere else, at the two
  doors a brush transform can come through: `create_brush_from_info()`, which is
  undo restore, duplication, prefab instancing, `.map` import and `.hflevel` load,
  so levels already on disk are repaired as they load; and the brush change
  tracker's reconcile, which is where an edit Godot owns is settled, so a gizmo
  drag or an Inspector edit is repaired on release. The fold is bookkeeping, not a
  move: `basis * H` paired with local vertices reflected by `H` leaves every world
  vertex exactly where it was, and each face's material, UV offset, scale and
  rotation travel to the face that takes its place, so the brush looks identical
  from the world. Measured through all three local axes in turn, and all three
  agree. A mapper who typed a negative into one scale field gets that field back
  positive and no turn behind it; a gizmo drag cannot say which axis it was, so
  that one arrives with a half turn it did not have, in the right place, the right
  shape and the right way out. A brush carrying a sculpted displacement is refused
  with a warning rather than repaired, the same refusal Flip makes, because the
  displacement grid is indexed against its face's corner order.
- **One subtract brush no longer costs the whole level its per-face materials**
  (#693). Cutting a window into a wall cost every other brush in the map its
  texturing. The face-material path has no boolean stage, so any cutter anywhere
  moves the whole bake onto CSG, and CSG resolved one material per brush: six
  brushes with six materials each baked to one material and a hole. On a real map
  the first cut goes in early and the checkbox stays ticked the whole time, so
  the path a mapper actually works on was the one that never carried their
  texturing. CSG was never the reason. It keeps a material per face, and a
  `CSGMesh3D` takes one from each surface of its mesh and writes it through the
  boolean - it was the `material` this code assigned to every shape that
  collapsed them all into one. A textured brush now enters the CSG tree as a mesh
  with one surface per material, built from the same `snapshot_brush_faces()` the
  face-material path uses, so the two paths cannot disagree about what a face is
  painted with. Untextured brushes keep the prefab primitive they have always
  been cut with, and a brush whose faces do not all triangulate goes back on the
  primitive too, because a hole costs the face path one invisible face and costs
  a boolean the whole result. The interior a cut exposes is a new surface nobody
  textured and still bakes with no material on it. The `user_message` warning
  that the face materials were dropped is gone with the behaviour it described:
  it would now be a lie, and it sent a mapper looking for a setting to change
  with nothing wrong to fix.
- **Validate reports two brushes in one level sharing an id** (#696). Saving a
  piece of level as its own scene and instancing it twice puts the same set of
  brush ids in one scene tree, because a saved scene freezes the ids it had. The
  report asked whether that should be fixed by re-minting on entry or by scoping
  the lookups. Measured first: the lookups are already scoped. Each instance has
  its own brush cache and its own containers, each copy resolves its own
  children, adding the second changes nothing in the first, and both bake. So the
  answer is the rule rather than a patch, and it is written down now: **a brush id
  is unique within one level, not within a scene**. Re-minting was the other
  option and is deliberately not taken, because it makes ids unstable across loads
  and the prefab system tracks by stable UID for that reason; a piece that came
  back with different ids each time would stop being the same piece. What that
  leaves genuinely broken is the case nothing was looking at: two brushes in *one*
  level answering to the same id. The cache is keyed by it, so the second to
  register overwrites the first and one of the two cannot be addressed at all, by
  a visgroup, a group, a hollow or array record, `nudge_brushes_by_id`,
  `tie_brushes_to_entity` or the Console. A hand-edited `.hflevel`, a `.tscn` where
  a `DraftBrush` was copied with Godot's own node duplication, or a record naming
  the same id twice all produce it. Validate names the id. No auto-fix: re-minting
  one of a pair silently re-points whichever records meant it.

- **A vibe scenario that breaks stops reporting clean** (#739). The sweep grades
  each scenario on its exit code, and a scenario that hits a GDScript error still
  reaches `quit(0)`. So a broken one was reported clean, which is worse than a
  failure, because in the summary it is indistinguishable from a real pass. It
  hid two things. `prefab-links` called `set_override()` for two releases after
  that mechanism was removed in #582, so its whole override section was dead.
  `status-board` was the worse one: it had already written the detector for the
  defect it was hitting, and because GDScript has no exception handling the throw
  unwound the scenario past its own `flag()` call. A run whose output carries a
  `SCRIPT ERROR` is graded as one now, and the sweep exits 1. That marker rather
  than the engine's broader `ERROR:`, because scenarios provoke engine errors on
  purpose: of the 142 logs sitting in `.vibe/`, thirteen carried an `ERROR:` and
  two carried a `SCRIPT ERROR`, and both of those were real. There is no way to
  mark one as expected, because that is how a detector stops detecting.
  `run_vibe.py --selftest` checks the grading still grades, and CI runs it beside
  the other guards.

- **A `.hfmaterials` file that is not a palette is refused rather than thrown on**
  (#739). `var mat_paths: Array = parsed.get("materials", [])` is a runtime error
  when the value is not a list, so a `-> bool` function unwound and handed back
  null: callers that tested the result got a falsy value by luck rather than by
  design, and nothing told anyone the file was unusable. It returns false and
  says why, and the palette that was already loaded survives the refusal.
  `library_is_readable()`, which is asked before the load is committed as an undo
  action, refuses the same files, so a pre-flight can no longer clear a file the
  load then rejects.

### Added
- **Copy and paste** (#703). `hf_keymap.gd` bound `duplicate` to Ctrl+D and
  nothing to Ctrl+C or Ctrl+V, and the only operations in the codebase made a
  copy in place, in the same level, immediately. That covers one of the two
  things duplication is for. The one it did not cover is taking a room out of one
  level and putting it in another, which is how people move work between maps and
  which every editor in this lineage has. **Ctrl+C** puts the selection on the
  clipboard and **Ctrl+V** places it, where it was copied from, and selects what
  it placed so the first drag moves the new piece. The clipboard is a prefab
  without a name: the same capture, so a copied piece arrives with its entity
  wiring, its brush entity ties and a record of what each material slot meant,
  and pasting into a level with a different palette resolves those against the
  destination. What a prefab has and this does not is a name, a place in the
  library, and a link back to a source; a pasted piece is geometry rather than an
  instance that follows an asset when the asset changes. Brush ids are minted
  fresh, so pasting twice gives two pieces the level can tell apart, and group and
  visgroup membership is not carried, because pasting into a level that has never
  heard of "West Wing" would otherwise put brushes in a group with no row in the
  panel. The buffer is a file in `user://` rather than something a level holds, so
  it survives closing a level and restarting the editor, and a piece copied in one
  project can be pasted into another. In the Scene tree, Ctrl+C is claimed when
  the selection is this plugin's, because Godot's own node copy would put a
  `DraftBrush` on its clipboard that a later paste would rebuild outside the brush
  registry with the id it already had; Ctrl+V is deliberately not claimed there,
  since it needs nothing selected and taking it from the Scene tree whenever a
  level is open would mean an ordinary node could no longer be pasted.

### Fixed
- **Undo stops repainting a level that did not change** (#705). Ctrl+Z on a
  900-brush map cost 195 ms. The reported cause was that a restore rebuilds the
  whole level, and that has not been true since #600: the reconcile keeps every
  brush whose record is identical to what it would capture right now, and on
  that map a one-brush edit rebuilds exactly one. Measured, all 900 were kept and
  none rebuilt. What the time actually went on was the line after it.
  `restore_state()` called `set_materials()` whatever the snapshot held, and
  `set_materials()` ends in a rebuild of every brush preview in the level: 141 ms
  of the 188, spent repainting the brushes the reconcile had just decided to
  keep, from a palette nobody had touched. It only happens when the palette is
  part of what changed now. A brush that does need rebuilding is rebuilt further
  down and gets its preview there, so nothing was depending on that refresh to be
  correct. **Undo on that map is 51 ms**, and 48 of those are the reconcile
  working out that there is nothing to do. `big-level` records the split and
  flags a restore that costs more than the decision does, which is the check that
  would have caught this.

- **A `.map` keeps which way up it is crossing between editors** (#733). `.map`
  is Z-up across the whole Quake family and Godot is Y-up. Nothing converted, in
  either direction, so a corridor drawn 112 units high arrived 3.5 metres deep
  and one metre high, and a floor exported from here opened in TrenchBroom as a
  wall. It went unnoticed for a long time because it is symmetric: out of
  HammerForge and back came home, and only the crossing was wrong, which is the
  only thing the format is for. The turn is a rotation about X, so the file's
  `(x, y, z)` is `(x, z, -y)` here and the reverse on the way out. Being a
  rotation it leaves handedness alone, so the winding reversal is untouched by
  it. That rotation rather than another because it keeps the level looking from
  above exactly as it did in the editor it came from; Func_Godot uses a cyclic
  one which is equally correct and which puts the map down at ninety degrees to
  the way it was drawn, and that shows the moment a piece is imported next to
  geometry that is already there. A point entity's origin takes the turn for the
  same reason it takes the scale. An `angle` does not, because it is a bearing in
  the file's own horizontal plane and would need turning as a direction rather
  than as a point. The Valve 220 texture axes do take it: the reader works the
  texture coordinate out by projecting the point onto those axes, and turning
  both by the same rotation leaves that projection alone, so the UVs come out of
  the conversion exactly as they went in. An export records which way up it wrote
  in `worldspawn`, so a file that says it is already this project's way up is
  left alone. One that says nothing is turned, because every editor other than
  this one writes the format's own axes. A `.map` exported by an older build
  carries this project's axes and does not say so, and nothing in it tells it
  apart from a file another editor wrote: export it again from a current build
  rather than relying on the import to guess.

- **A `.map` keeps its size crossing between editors** (#713). A `.map` file
  carries bare numbers and never says what a unit is. Every editor that writes
  one is on Quake units, where a player is 56 to 72 tall and the grid steps in
  16s, and this project has been on Godot's metric scale since #625, where the
  playtest player is 1.6. `MapIO` copied the coordinates through, so a corridor
  drawn two players high arrived seventy players high with its spawn twenty-four
  units off the floor, and the level was unusable without rescaling every brush
  by hand. The export had it in reverse: a room from here was smaller than the
  other editor's smallest grid step, so every vertex of it snapped onto the same
  point. Both directions now convert, through a **Map units/m** row in the File
  section that defaults to 32. That is the figure Func_Godot uses for the same
  exchange, and it puts a 56-unit player at 1.75, which is the same person as
  this project's 1.6. A point entity's origin takes the conversion because an
  origin is a position in the same space as the plane points; a door's `speed`
  does not, because that is a distance per second in the source game's units and
  only that game knows what it meant. The texture scale takes it as well, since
  a `.map` reader divides the projected point by that field and a room scaled
  without it would come out the right size covered in dust. An export records
  what it used in `worldspawn`, so reopening your own file gives back the level
  you exported however the row has moved since, and moving the row between an
  import and an export rescales the level on purpose. The conversion lives in
  `HFFileSystem` rather than in `MapIO`, which reads and writes the format and
  converts nothing it was not asked to.

- **CI stops going red on a download**. Shard 4 failed on d1b6ca5 with exit code
  8 from `wget`, while the other three shards fetched the same URL a second apart
  and got it. No test ran in that shard, and main went red on a commit whose
  tests all pass. The step made one GET with no retry, and `wget` does not retry
  an HTTP error response on its own: `--tries` treats one as fatal, which is why
  the attempt gave up in half a second. `-q` hid which code came back, so the log
  had nothing to say about what happened. Four shards each fetch that file, so
  every run carried four chances to lose the merge gate to a bad second on a host
  nobody here owns. The step now retries the transient codes, retries the whole
  fetch up to three times for anything else, checks the zip is whole before
  accepting it, and leaves the server's answer in the log. The actionlint
  download beside it gets the same treatment.

- **A brush entity's properties can be set** (#728). `func_door` declares
  `speed`, `wait`, `angle` and `locked`, `func_button` declares `wait` and
  `locked`, and none of them could be given a value in the editor. Two things
  were in the way and either would have been enough: a brush tied to an entity
  class is a brush, so the Entity Properties panel never opened for it, and the
  setter behind that panel wrote to an `entity_data` meta a brush does not
  have - the call was accepted and dropped, with no error anywhere. The storage
  existed the whole time under `brush_entity_data`, which the brush capture and
  the `.map` writer both read and only a `.map` import ever wrote, so a door
  imported from TrenchBroom arrived with its speed and a door drawn here could
  never be given one. The editor writes that key now, rather than a second key
  meaning the same thing.

- **An idle autosave writes nothing** (#716). `saved_at` was stamped when the
  level was captured, inside the payload the save dedupe hashes, so every save
  produced a different hash however little had changed. The mechanism that exists
  to stop an idle autosave rewriting the same bytes could therefore only ever
  fire for two saves inside one wall-clock second - which is not a case anybody
  hits on purpose - and never on the multi-minute schedule it was written for.
  The stamp now goes on as the file is written, so the hash covers the level and
  not the clock, and the file still records when it was saved. The hash is taken
  from the state rather than from its JSON, which is about thirty times cheaper
  on a level-sized structure; it is sensitive to the order keys were inserted in
  where JSON's sorted form is not, and that is the safe direction to be wrong in,
  because it means a level is written again rather than not written at all.

### Added
- **A sound entity** (#704). `HFIOPresets` ships "Door Open -> Light + Sound" as
  the first of its six built-in connection presets, and there was no class a
  mapper could map its `sound` tag to - the preset was unfillable out of the box.
  `ambient_sound` is an `AudioStreamPlayer3D` with a stream, a volume, a max
  distance and an autoplay, and `Play` and `Stop` as inputs. Those two are
  exactly the engine methods the guard refuses, so the class declares them
  through `input_methods` the way `logic_timer` does. A property can also name
  the resource class it holds, through `resource_properties`, so the path a
  mapper types for a stream is loaded rather than assigned as a string - which
  did nothing at all.

### Fixed
- **A door moves when it is opened** (#687). `func_door` describes itself as
  "Geometry that moves when opened" and ships `speed`, `wait` and `angle`.
  Nothing read any of them: the bake produced a plain `MeshInstance3D` with no
  script, so `HFIORuntime` fell through to the last branch of its delivery chain
  and emitted a signal nobody was connected to. A mover class now bakes into a
  holder of its own carrying the mesh and the collision together - a door that
  slid its mesh and left its collision behind would be worse than one that does
  not move - with a script that slides it its own width along the angle at the
  speed it was given, closes itself after the wait, and raises `OnOpen` and
  `OnClose` as it goes. The holder takes the authored name, because the mesh
  under it cannot act on an input and `_cache_entities()` keys a node by its name
  as well as by its metadata. A brush entity's properties can only be set by a
  `.map` import today (#728), so a door drawn here runs on the class defaults.

### Fixed
- **The Physics Layer dropdown says what each entry costs** (#695). Two of its
  three entries bake a world that nothing with default settings collides with:
  `CharacterBody3D`, `RigidBody3D` and every `PhysicsRayQueryParameters3D` in
  Godot default to mask 1, so a level baked onto layer 2 or 3 is one the player
  walks through, and "Debris/Prop" reads like a categorisation rather than like
  that. The entries now name the consequence. A baked `StaticBody3D`'s mask is 0
  as well: it never moves, so a mask buys it nothing and only widens the
  broadphase, and copying the layer into it meant the one dropdown moved two
  things at once. And the spawn validator asks the level which layer it bakes
  onto instead of falling back to 1, so a level on another layer no longer has
  its spawn reported as floating in space - which named the wrong problem.

- **A visgroup list comes back in the order it was made** (#706). Every name
  survived a `.hflevel` round trip and came back alphabetised, and reshuffled
  again the moment a new one was added. The registries are `Dictionary`s and a
  level bundle is JSON, where `JSON.stringify` sorts object keys - so the order
  went in and did not come out. That order is not arbitrary: on a real map it is
  roughly the order the level was built, shell then detail then lighting, with
  the wing being worked on today at the bottom where it is easy to find. The
  order is now recorded beside the registry rather than inside it, so a visgroup
  can be called anything, including something that looks like a bookkeeping key.
  Groups had the same shape and get the same treatment. Paint layers were already
  an ordered array and never had the problem. A file written before this has no
  order recorded and loads exactly as it did.

### Fixed
- **The player can climb the stairs the plugin builds** (#711). The plugin ships
  a Stairs generator, a Spiral Stairs generator and an auto-connector that builds
  stairs between height layers - and the character that has to walk them could
  not climb a step of any height. Godot's `CharacterBody3D` has no automatic
  step-up, so a vertical face is a wall to it whatever its height: a five
  centimetre riser stopped the player exactly as a twenty-five centimetre one
  did. `playtest_fps.gd` now runs a step-up before each `move_and_slide()`, with
  a `max_step_height` beside the walk speed defaulting above the connector's own
  stair height. Three tests decide it: the motion is blocked at foot level, clear
  from a step height above, and there is something to land on up there. A wall of
  the same total height as a staircase is still a wall.

- **The navmesh has the two settings that decide whether an agent can use the
  stairs** (#701). `bake_navmesh()` set four properties on the `NavigationMesh`
  and left `agent_max_climb` and `agent_max_slope` at Godot's defaults, which
  mattered because the plugin builds stairs itself: the auto-connector's default
  step is 0.25 and so is Godot's default max climb, so every generated staircase
  sat exactly on the limit and a mapper raising the step for a chunkier stair put
  it out of reach of every agent in the game. Both are now spins in the Manage
  tab beside the other four, defaulting to Godot's values, and Bake Check reports
  the combination that produces stairs nothing can use.

### Added
- **Validate reports two brushes in the same place** (#702). The most common
  mistake in brush editing had no check: Ctrl+D followed by a drag that did not
  take leaves the copy exactly on the original, so nothing looks wrong in the
  viewport, and what the level gets is doubled triangles over the whole overlap
  and z-fighting on every coincident face - which shows up in the game as
  flickering surfaces that are hard to trace back to their cause. The check is
  the narrow one: position, size and shape all matching within an epsilon, which
  catches the duplicate left in place without flagging ordinary intersecting
  geometry, because brushes are meant to intersect. No auto-fix, since deleting
  one of a pair is a guess about which one the mapper wants.

### Added
- **Export Game Scene** (#697, #698). The playtest export was the only path in
  the plugin that turned an entity marker into the real node it stands for - a
  `light_point` into an `OmniLight3D`, a `logic_timer` into a `Timer` - so it was
  also the only way to get a scene that could be shipped, and it always appended
  a debug FPS controller, a flat grey environment and a fallback sun, with no
  argument to leave any of them out. The mapper's options were to delete three
  nodes by hand after every export or to write their own exporter. There is now a
  button beside Export Playtest Build that writes the same geometry, the same
  real entity nodes and the same `HFIODispatcher`, with none of the rig, next to
  the level's own scene and named after it. The environment and the sun are a
  matter of taste; two character controllers in one scene is a bug in the game.

- **A "Shipping a Level" guide** (#709). Which of the files beside a level is the
  level, what the export writes and what it leaves out, how to get lighting baked
  in, which bake options a shipped level wants and what each costs, what to turn
  off, and how to raise an output from game code. Every one of those had an
  answer and several were only discoverable by reading `level_root.gd`.

### Fixed
- **A bake says when a cutter drops the face materials** (#694). A level with a
  subtractive brush in it takes the CSG path, which resolves one material per
  brush rather than one per face, and the only thing that said so was a line in
  the Console. The Use Face Materials checkbox stayed ticked and the Manage tab
  looked exactly as it had. The branch immediately below it has always sent a
  `user_message` for the mirror case - the checkbox turned off by hand while
  faces carry materials - so the case a mapper chose got a message and the case
  they hit by accident, by drawing a cutter, got nothing. Both now say so, and
  the new one names the cause and how many brushes caused it. It is said only
  when faces actually carry materials, which is the same guard the other branch
  uses: a level with nothing painted on it loses nothing by taking the CSG path.

- **A lightmap unwrap that fails says so** (#700). `ArrayMesh.lightmap_unwrap()`
  returns an `Error` and mutates the mesh in place, and the code checked whether
  it had returned a `Mesh` - so the branch was dead and the `Error` went into a
  local nobody read. The unwrap worked anyway, because the two names are the same
  object. What was missing was the failure: `ERR_UNAVAILABLE` when the engine has
  no unwrapper and `ERR_CANT_CREATE` when it cannot lay the mesh out. Either way
  the bake reported success, the Lightmap UV2 checkbox stayed ticked, and a
  `LightmapGI` over the result baked that surface black with no explanation.

- **A level in a game scene is a level, not a playtest** (#699, #689).
  `auto_spawn_player` defaulted on and `LevelRoot._ready()` acted on it outside
  the editor, so a scene with a `LevelRoot` in it, loaded by a built game, added
  a debug FPS controller with its own camera and HUD beside whatever player the
  game already had, and rebuilt the whole level from source brushes at load
  rather than showing the `BakedGeometry` the scene carries. Beside it,
  `_setup_runtime_reload()` started a timer that stat'd
  `res://.hammerforge/reload.lock` twice a second forever - 120 times a minute
  per level root, under a dot directory an export does not ship, so the answer
  could never be true - and a hit rebuilt the level mid-play. Both were gated on
  "not in the editor", which is the shipped game and nothing else. The default is
  now off, and both are gated on `OS.has_feature("debug")`, so a release build
  takes neither whatever the properties say. Test Level is unaffected: the
  playtest export has always built its own player and never read this property.
  The status board said so too - it reported a level with the setting off as a
  problem, on the grounds that Test Level would start with no player - and now
  reports what is true, that a level with no spawn point gets one at the origin.

- **A model a mapper points at appears** (#690, #691). `prop_static` is the
  documented way to put a model in a level - "Set Scene to the mesh or scene to
  show" - and the path it stored was saved, exported and never loaded, so the
  level stayed empty in the viewport, in the bake and in the playtest, with no
  error anywhere. A definition can now name the property an instance chooses its
  own model with, and `prop_static` names `scene`: the path is instantiated as
  the entity's preview and as the node the bake and the export carry, and one
  that does not resolve leaves the class's own preview in place and says so
  rather than showing nothing. The scatter brush had the same shape from the
  other side: its picker offers `.glb` and `.gltf`, which is the format an artist
  hands over, Godot imports both as a `PackedScene`, and the loader kept the
  resource only if it was already a `Mesh` - so the pick was accepted by the
  dialog, dropped by the loader, and reported at Scatter time as "Pick a mesh
  first", naming the step the mapper had just done. A picked scene now scatters
  the first mesh inside it.

- **An entity definition is data, not a whitelist**. `entities.json` was read
  into a model that had a field for ten keys and wrote back only those, and that
  model was the only thing that populated the level root's definitions. So
  `preview`, which is how an entity draws itself in the viewport, and
  `input_methods`, which is how a class says an input names an engine method
  (#714), were both parsed, both read for, and neither survived the trip.
  Anything the model does not model is now carried through untouched. The keys it
  does model still win, because several are normalised on the way in - reading
  the raw `class` back first is what once made `light_point` come back as
  `OmniLight3D`.

- **A prop's model is packed once**. Making every node under the exported scene
  belong to its root is what keeps baked geometry through `pack()`, and doing it
  to the inside of an instantiated scene writes those nodes out beside the scene
  instance as well, so the saved scene held the model twice and loaded it twice.
  Ownership now stops at an instantiated scene, which brings its own children
  back with it. Nothing hit this before, because nothing instantiated a scene
  into an export.

- **Save As writes the file** (#688). Saving a level that had not changed since
  the last save wrote nothing, whatever path it was given, and reported success.
  The dedupe that stops an idle autosave rewriting the same bytes compared one
  hash with no record of which file produced it, so Save As to a new name, a
  numbered backup at the end of a session and a copy for a teammate all closed
  the dialog and left no file. The key is now the destination, the compression
  setting and the hash, because all three decide the bytes on disk. A write that
  failed no longer records its hash either, which had the same effect one step
  later: the retry matched the failed attempt and was skipped as a rewrite.

- **The I/O graph a mapper wires now runs** (#686). Every output wired in the
  Objects tab was dispatched correctly and never started. The bake built the
  `Area3D`, `wire()` built the connection table, `HFIORuntime` delivered
  faithfully, and nothing ever called `fire()`, so the whole tab -- the panel,
  the wiring visualiser, the six connection presets -- produced a graph that was
  correct, saved, exported and inert. A trigger volume now raises its own:
  `trigger_once` and `trigger_multiple` fire `OnStartTouch` when a body enters
  and `OnEndTouch` when one leaves, and `trigger_once` fires the first time only,
  which is the one thing separating it from `trigger_multiple` in the bake.
  Pressing is not something the plugin can raise on anybody's behalf, so the
  playtest player does what a game's player would: a ray from the camera on its
  Use key, and `fire(name, "OnPressed")` on the `func_button` it finds. A regular
  editor bake attaches a dispatcher too, so the trigger signals are connected at
  runtime only.

- **An entity class can say which engine method an input means** (#714).
  `logic_timer` shipped `Start` and `Stop` against a `Timer`, and those are
  exactly `Timer.start()` and `Timer.stop()` -- the two methods the guard that
  stops an input called `QueueFree` deleting its target exists to refuse. The
  class was unusable as shipped: the dropdown offered both, the visualiser drew
  the wire, and firing either printed a warning and emitted a signal nobody was
  connected to. A definition can now carry `input_methods` naming the engine
  method behind an input, the way a property carries `maps_to`. The grant is per
  class, so nothing widens what a free-text input name can reach. A granted
  method is called in the shape the engine declares it: `Timer.start()` takes a
  float, and handing it the empty string was an argument error that stopped the
  delivery dead, so a method that can take no argument is called with none, and
  an authored parameter is converted to the declared type.

### Changed
- **`func_detail` is the cheap option it reads like** (#712). Its own description
  is "Geometry the structural bake skips. For trim and clutter that should not
  cut the world", which is most of a finished map, so the class gets applied to
  hundreds of brushes - and every one of them got its own `MeshInstance3D`, its
  own `StaticBody3D` and its own `CollisionShape3D`. Five walls and eighty crates
  baked to eighty-one draw calls and eighty-one bodies where the same room left
  structural made one of each, and it was linear: three hundred detail brushes
  shipped nine hundred nodes. They now go through the same material grouping the
  structural path already uses, into one mesh per material and one body, with a
  convex hull per brush so a pile of clutter still collides as the separate
  solids it is. A detail brush carrying an entity name or I/O outputs keeps a
  node of its own, because that is the address the runtime finds it by.

- **An uncompressed level is one value per line** (#708). Save compression
  exists so a team can turn it off and put the level in version control, and what
  it produced was a single 140 KB line: one changed line in every diff, a
  conflict on that line for any two branches that touched the level, and a blame
  that named whoever saved last. Uncompressed bundles are now written with one
  value per line and keys in a stable order, so a level change reviews like any
  other file. Compressed is still the default and is unchanged, and the loader
  reads either form. Paint region sidecars stay compact whichever way the setting
  is set, since their chunks are flat arrays of one integer per texel.

### Added
- **A gate that can tell a call site from a mention** (#647). #609 and #610
  together were 66 dead declarations, and thirteen of those existed only because
  five architecture tests required them by name, so the codebase had a mechanism
  actively regrowing dead code. The tests are fixed; nothing stopped the next
  list accumulating the same way. The scan that produced those lists compared
  each name's occurrence count against its declaration count across the plugin,
  the suite, `tools/`, `docs/`, the README and the CHANGELOG, which treats any
  mention as a caller: `plugin.gd:_point_near_polygon_3d` was dead, had no
  caller, and the scan missed it because the name appears in prose elsewhere.
  `tools/check_dead_declarations.py` reads GDScript and nothing else. It strips
  comments and string literals in one left-to-right pass rather than one regex
  per construct, because stripping literals first lets an apostrophe in a
  comment swallow the code below it and stripping comments first lets a `#`
  inside a literal swallow the rest of the line, and both produce confident
  wrong answers. String dispatch is load bearing here, so literals are harvested
  separately and a declaration whose whole name is one of them is live:
  `call_deferred("_x")`, `Callable(self, "_x")` and `&"_x"` all still reach a
  method. Whole name, not substring, so prose inside a string keeps nothing
  alive. Reads are counted apart from writes, so a field that is written and
  never read is flagged, which is the half of #610 an occurrence count cannot
  see. Scene file signal connections count as uses. `tools/engine_virtuals.txt`
  is every virtual Godot declares, generated by
  `tools/dump_engine_virtuals.gd`, so an override the engine calls is not
  reported. A deliberate case marks itself
  `# hf-allow-unused-declaration: <why>`. CI runs the selftest before the check,
  the way the other four guards do.

- **A level says when its `.hflevel` and its `.tscn` have come apart** (#646). A
  level lives in two files written by two different commands: Godot's own Ctrl+S
  writes the scene, Save Level writes the `.hflevel`, and on open the scene wins
  because the scene is what Godot loads. So draw, Ctrl+S, draw more, Save Level,
  close without Ctrl+S, and the newer `.hflevel` sits beside the level unread
  with nothing saying so. Autosave puts a level in that state on a timer nobody
  chose, so it did not take a deliberate Save Level to get there. HammerForge now
  compares the two files' modification times on the frame the dock binds to a
  level, and puts a Console line and a toast on screen when the `.hflevel` is the
  newer one. It says it once per open rather than once per bind, because the dock
  rebinds every time a scene tab is switched, and by then the open scene has moved
  on and Load Level would cost whatever was done since. A level set to keep only
  its baked geometry loads its `.hflevel` on open by design (#624) and is never
  reported. Nothing is reconciled or merged: knowing the two disagree is the part
  that was missing.
- **A `.hflevel` records the scene it was saved from** (#646). Every level wrote
  to `res://.hammerforge/autosave.hflevel` until it was given its own path (#655
  has since made that default per level), so a newer `.hflevel` beside a scene
  was as likely to be the level next door's, and Load Level on it would
  overwrite the open level. The bundle now carries a
  `scene` field, and a file that names a different scene is not reported against
  this one. A file written before this carries no such field and is still
  reported, with a message that says it cannot tell which level it holds. The
  field is read only after the timestamps already say the file is newer, and it is
  read without `HFLevelIO.load_from_path()`, which renames a `.previous` back over
  a missing file: asking a question about a level must not recover one.
- **A level can choose what its scene keeps** (#624). HammerForge gives an
  `owner` to almost everything it makes, so Godot's own Ctrl+S writes the brushes
  and the geometry baked from them into the `.tscn`, and Save Level writes a
  third copy into the `.hflevel` beside it. A 100 brush level measured 261 KB of
  scene against 4 KB of `.hflevel`, and a bake added another 149 KB that is
  entirely derivable from the brushes already in the file. For a greybox session
  that is a megabyte of scene rewriting on every save, and it is what a mapper
  commits and what a teammate has to merge. There was no way to say keep the
  brushes and rebuild the geometry, or keep the geometry and let the brushes live
  in the `.hflevel`. **Scene Keeps** on the `LevelRoot` now says which:
  brushes and bake, brushes only, or baked geometry only. The default is
  unchanged and is the only one that needs no other file, because the bake has to
  be owned for a level to have geometry at runtime without the plugin, which was
  always deliberate. Changing it re-owns what is already in the level, so the
  next Ctrl+S writes what the setting says rather than what the level happened to
  be built with. Baked geometry only is refused when there is nowhere to put the
  brushes: a level with no `.hflevel` path keeps them regardless, because
  dropping a level's only copy of its brushes is not a trade worth making
  silently, and the setting says why it is not doing what it was set to. That
  mode is also the one whose scene cannot open on its own, so it loads its
  `.hflevel` when the scene comes up, and says so rather than opening empty when
  the file is not there. The data portability guide now also states the thing it
  never did: on open the scene wins, because the scene is what Godot loads, so a
  `.hflevel` saved after the last Ctrl+S is not what comes up.

### Removed
- **Five private declarations nothing called** (#647), found by the new gate on
  its first run: `brush_instance.gd:_apply_additive_wireframe_overlay`, which
  described itself as a compatibility entry point for callers that do not exist;
  `dock.gd:_get_scene_history_id` and `plugin.gd:_select_faces_in_rect`, both
  one-line delegates with nothing on the other side; a test helper in
  `test_justify_uv.gd`; and a signal callback in `test_dock_decomposition.gd`
  shimming a signal that is no longer in `HFDockConnections.ROOT_SIGNALS`, which
  is the shape #647 describes. `plugin.gd:_select_faces_in_rect` was the
  mechanism itself, not just an instance of it: an architecture test listed
  `HFPluginSelectionInput.select_faces_in_rect` among the entry points
  `plugin.gd` must delegate, and the wrapper existed only to satisfy the list.
  The rule written above that list already excluded it, because `handle_release`
  calls it inside the same module, so the entry is gone rather than the rule.
  The Displacement paragraph in DEVELOPMENT.md
  still pointed at `plugin.gd:_point_near_polygon_3d()`; that function moved to
  `plugin_paint_input.gd` and lost its underscore, and the stale line is exactly
  what kept it off the old list.

### Changed
- **The test suite runs in four shards** (#648). A CI run was 6 minutes 24
  seconds at the median, and 94% of that was one job: the GUT suite took 386
  seconds while the two lint jobs finished inside 73. Per-script timings say
  there was nothing to optimise -- 222 scripts, median runtime 0.99s, 112 of
  them under a second, and the slowest single file 21s -- which is exactly the
  shape that divides instead. `tools/shard_tests.py` splits the scripts
  round-robin over their sorted names into four legs of 56/56/55/55 scripts,
  and an aggregate job adds the four logs back together. The measured run:
  shard jobs of roughly 1m45s to 2m05s, an aggregate job of 10s, and
  GDScript Lint & Format at 1m4s -- a total of 2m21s against 6m33s for the
  equivalent run on main. Coverage is unchanged: the same 222 scripts, 4,093
  tests and 19,729 asserts run, 4,086 passing, identical to the single-job run,
  and the aggregate refuses to publish a total unless the logs account for
  every script, because a shard that ran short would otherwise write a smaller
  suite into all five documents as measured fact. Path filtering was measured
  and rejected instead: 49 of the last 60 commits touch both `addons/` and
  `tests/`, and all three job names are required checks, so a filtered job
  reports `skipped` and leaves the pull request unmergeable for good.
- **One world unit is one metre, and the drawing side now agrees** (#625). Two
  scale conventions were in the project at once and the seam ran through the core
  loop. The playtest player, the spawn checks, the bake settings and all five
  shipped examples were metres; the drawing defaults were Quake-family units. A
  default brush was 32 units against a 1.6 unit player, so the first thing anyone
  drew was twenty player heights tall, one grid step was ten, and a room drawn on
  the defaults was a cathedral nobody could climb out of. Draw, then Test Level,
  was the loop that broke. The drawing side moved onto the runtime's scale rather
  than the other way round, because the runtime, the examples and Godot's own
  physics defaults were already there: grid snap 0.5, a 2 x 2 x 2 default brush,
  the quick snap buttons 0.1 through 8 instead of 1 through 64, and generator
  defaults that are sizes a person could walk through: a 3 m arch, and a 1.5 m
  wide flight of 0.2 m steps. Every length field's minimum and step came down with
  them, because a minimum of 1.0 meant the thinnest wall the dock could offer was
  a metre and the grid SpinBox could not be typed a fraction at all. The maximums
  are untouched, so a level saved with a 128 unit arch still loads and still
  regenerates. Two more numbers were on the seam and moved with it: the geometry
  snap threshold, which at 2.0 would have been four grid steps and swallowed the
  grid whole, and the auto connector's stairs-versus-ramp threshold, whose own
  comment recorded that it was raised to 32 for the old grid. At this scale no
  level reaches 32, so Auto was Ramp everywhere. It is back to the 2.0 that
  comment says it started at. The viewport context menu's grid list and the dock's
  quick buttons now read one shared ladder instead of a hard-coded copy each; the
  menu carried its value inside the item id, which is an int and could not hold a
  fraction. A level saved before this keeps the grid and sizes it was built with, because
  they live on the `LevelRoot`, so only a new level starts on the new defaults.
  The user guide now opens with a **World Scale** section that says how many units
  a person is, which is the one number a level editor's documentation has to have.
- **Two release gate checks corrected by running the gate** (#593). The first
  execution of the document, rather than another addition to it, and it found
  two of its own lines describing things the product does not do. Create Starter
  Level is two undo actions, not one: the first Ctrl+Z takes the starter contents
  and leaves the `LevelRoot` standing, which is what the long checklist's section
  1b always said, so the gate line was the wrong half. And a clean bake writes
  nothing to the Console Log. `HFLog` has only `warn()` and no `info()`, and its
  own comment calls it a mirror for what HammerForge warns about, so a successful
  bake has no way to reach the Log at all. Both the gate line and section 0a
  claimed it did. The Bake status row is the thing that actually reports a bake,
  and it names how long it took. The gate record now carries what the run covered
  and what it did not, including that the resize-handle drag was signed off
  rather than executed.
- **The editor smoke checklist is now a short gate plus a long reference, and the
  gate is enforced** (#593). 599 steps across 60 sections, 57 commits since March,
  and nothing ever ran it. Every edit had the same shape: a fix lands, a line
  describing the new behaviour is added, and that line becomes the evidence the
  case is covered. #592 is the proof it was not being read from - a brush click
  threw the editor onto the HammerForge main screen for eleven days, straight
  through a dozen steps in section 2b that each need a brush clicked in the 3D
  viewport, while the document was edited five times inside that window. The top
  of the file now says what it is: a ten-minute Release gate that is run, and a
  reference below it that is not and never has been. `release.yml` reads the
  gate's recorded version and fails the release when it does not match the
  version being shipped, because a warning nobody reads is the thing being fixed.
  The rule behind it is in `DEVELOPMENT.md`: adding a line to the checklist is
  not evidence that a case is covered, so put the check where it can fail on its
  own. The 599 steps are kept rather than cut - they are the only record of what
  has not been verified, and deleting them would lose that while making the
  document look healthier.

### Removed
- **Fifty-seven private functions and nine fields that nothing used** (#609,
  #610). `plugin.gd` and `level_root.gd` are documented as thin coordinators
  whose named one-line delegates exist to be called by name, and the rule beside
  that is that a delegate with no caller gets deleted. These had drifted past it.
  The whole viewport drop path in `plugin.gd` was a second layer: Godot calls
  `_can_drop_data` and `_drop_data`, those hand straight to
  `plugin_drop_handler.gd`, and its own `drop_data()` dispatches the four payload
  kinds itself, so the eight wrappers in front of that dispatch were reachable
  from nothing.

  Five architecture tests were keeping much of this alive, which is the more
  useful half of the finding. Each enumerates a module's methods and asserts
  `plugin.gd` contains a delegation string for every one, and the lists had grown
  to include helpers the modules call themselves: `update_preview`,
  `apply_value`, `do_displacement_stroke`, `point_near_polygon_3d`,
  `update_prefab_hover`, `move_selected_vertical`, `normalize_editor_selection`,
  `expand_native_group_selection`, `same_node_selection`,
  `sync_hf_selection_if_empty`, `face_screen_center`, `show_quick_property`,
  `ensure_vertex_overlay`. The only way to satisfy the assertion was a wrapper
  nothing called, so tests written to enforce that `plugin.gd` stays thin were
  requiring it to be thicker. Each list is now the entry points `plugin.gd`
  actually owns, and the drop test additionally asserts that `plugin.gd` does not
  contain the payload type strings, which is the property "thin delegate" was
  reaching for and the enumeration never checked.

  `HFPluginSelectionState.selection_has_brush()` and `selection_has_entity()` went
  too. Their only caller was the dead wrapper, so removing it made them provably
  dead in the same pass.

  Two of the fields are public on registered custom types, so both are a break
  for any script that touched them, and both earn it. `DraftEntity.entity_properties`
  was a second name for `entity_data` that nothing in the plugin used, and two
  names for one dictionary can only ever diverge. `LevelRoot.drag_active` is the
  worse of the two: its setter called `input_state.cancel()` while the canonical
  `cancel_drag()` is `input_state.cancel()` **and** `_clear_preview()`, so setting
  `drag_active = false` did half a cancel and left the preview brush orphaned in
  the scene. It was a latent bug rather than dead weight. `LevelRoot.grid_plane_axis`
  and `dock.gd`'s `_entity_props_entity` were written and never read, so the
  writes went with the declarations.

  `map_io.gd`'s `_format_face_line()` was a drifted second copy of the `.map`
  face line: it takes three arguments and hard-codes the texture and the
  `0 0 0 1 1` tail, while the three adapters take `(a, b, c, texture, face_data)`
  and read real UV data off `FaceData`. Nothing could have called it even by
  accident, and a second copy of the export format is a trap for whoever fixes
  the exporter next.

### Fixed
- **A turn keeps a face's texture the right way round** (#684). #683 moved the
  projection into the level, which means a face can now change which Box UV axis
  it resolves to. `projection_axes()` is right handed for PLANAR_Z against its
  own normal and left handed for the other two, an asymmetry the file already
  noted, and it could not matter while a face's axis was fixed. A wall yawed a
  quarter turn moved from PLANAR_Z to PLANAR_X and came back mirrored along U,
  with the measured direction the exact negation of the carried one.
  A face remembers the brush orientation its UVs were laid out against, and the
  handedness change is folded into `uv_scale` at the moment the axis changes.
  Nothing on disk changes meaning and no saved level is migrated: the correction
  lives in a field that was already persisted, and a level reopens at the
  orientation it was saved at, so nothing is reconciled and nothing moves.
  Which of the two axes to reverse is not a fixed answer. A yaw from PLANAR_Z to
  PLANAR_X reverses U and leaves V; a roll from PLANAR_Y to PLANAR_Z reverses V
  and leaves U. The old projection's axes are carried through the turn the brush
  made and compared against the new one's, and a turn that does not land them on
  each other is a skew no planar projection holds, so it is left alone rather
  than guessed at.
- **Texture Lock carries a turning brush's texture, the way it carries a moving
  one's** (#684). The compensation was subtracting the turn where it now has to
  cancel it, so a box's top and bottom came back turned the wrong way by twice
  the angle -- at ninety degrees, exactly reversed.
  This is the rotation half of what #653 was for translation. While UVs were
  projected from a brush's own vertices, doing nothing held a texture on the
  brush and the compensation was what let go of it, so #355 settled Texture Lock
  as the setting that pinned a face to the world. The two have swapped. Doing
  nothing now holds a texture where it is in the level, and the compensation is
  what carries it round, so ticked means for a turn what it already means for a
  move: the texture goes with the brush. Unticked keeps it on the world grid.
  Both behaviours are still reachable and the label is true of both.
  `tests/test_texture_lock.gd` drove `adjust_uvs_for_rotation()` on a brush that
  had not moved, so it measured the old projection and passed either way. It
  turns the brush now. That also turned up that
  `NOTIFICATION_TRANSFORM_CHANGED` is deferred and has not arrived by the time
  the compensation runs, which is why `rebuild_preview()` syncs the faces rather
  than leaving it to the notification.
- **A texture runs across a wall built from more than one brush** (#652, #653). A
  face's UVs were projected from the brush's own vertices, and a brush's local
  vertices do not know where the brush is. Two brushes the same size therefore
  had the same UVs wherever they sat, so a wall built from three panels was three
  copies of one patch of texture with a hard restart at every brush edge, and a
  four copy array was four. Building a surface out of several brushes is the
  fundamental move in this style of editor, and it is invisible in a one brush
  test.
  The planar projections read the vertex's position in the level now. The three
  panels land on `u[-64..64]`, `u[64..192]` and `u[192..320]` and butt up.
  Cylindrical is deliberately left in the brush's own space: its angle is
  measured about the brush's axis, and taking that in world space would spin the
  texture as the brush moved.
  Box UV resolves its axis in the space the projection is taken in. It picks the
  axis a face most nearly faces, and asking that in the brush's space while
  projecting in the level's is how a wall yawed a quarter turn kept `PLANAR_Z`
  and then projected world (x, y) onto a plane of constant x: every vertex got
  the same u and the texture smeared into a line. The same goes for the move
  compensation, whose `pos_delta` is a distance through the level. A brush that
  has not been turned resolves to the same axis either way, which is why this is
  invisible until something rotates.
  The brush is what tells a face where it is, from `NOTIFICATION_TRANSFORM_CHANGED`
  and from `rebuild_preview()`. The notification covers a transform set by the
  gizmo, by undo, by a generator or by a `.map` import without any of them
  knowing about it. `rebuild_preview()` covers the paths that fill `faces` by
  appending rather than assigning, so the setter never fires: a load, an undo
  restore, and the bevel, inset and vertex tools adding faces to a brush that is
  already placed. It runs before the `mesh_instance` guard, because a brush
  outside the tree still has UVs.
  **Treat as one** works as a result. Its whole job is aligning several faces as
  a single sheet, and `justify_selected_faces()` had the arithmetic right all
  along -- it computed a shared rectangle across every selected face and could
  not help, because all of those faces reported the same rectangle to begin with.
  Three panels in a row now take a third of the sheet each, in the order they sit
  in the level.
- **Texture Lock keeps the texture on the brush** (#653). It needed no code
  change, and the sign flip the issue proposed would have broken it. Under a
  local projection a brush that moved kept its texture whatever the checkbox
  said, and the compensation the checkbox switched on was the thing that made the
  texture slide off, so the control was inverted. Under a world projection the
  existing `uv_offset -= rotated_delta * uv_scale` is what holds the texture on a
  brush that moves, which is what the label promises. Ticked, the texture travels
  with the brush; unticked, the brush slides under it and the texture stays on
  the world grid. The resize half of the same function already worked that way,
  which is why the two halves of one function used to disagree.
- **Levels saved before that keep the texture placement somebody set** (#652).
  `uv_format_version` is 2. An offset used to measure from the brush and now
  measures from the level, and the two differ by wherever the brush is, so a face
  loaded below v2 folds its brush's placement back into `uv_offset` the first
  time the brush tells it where that is. That cannot happen in `from_dict()`,
  which is why the gate is on the face and the work is done by the brush.
  Only an offset somebody set is folded in. A face still on zero was never
  positioned by hand, and giving it one would put the panels of a wall back on
  the same patch of texture, which is the defect. Those faces take the new
  projection, which is the fix reaching levels that already exist. A rotated
  brush cannot be corrected by an offset at all, because world projection is a
  different map there rather than the same one shifted; those faces keep their
  old look by baking it into `custom_uvs`, the way the v0 to v1 migration keeps a
  non-uniform scale.
- **A brush entity can be named, and a two leaf door is one door** (#668). A
  brush entity arrived in the level as a class string on each brush and nothing
  else, and three things that should follow from it did not.
  It could not be named. `find_entities_by_name()` checks brushes for an
  `entity_name` meta and says why in its own comment, and the `.map` exporter
  writes one, so the mechanism was complete except for a surface that set it --
  the only code that ever wrote the meta onto a brush was the `.map` *import*
  path. A door built in HammerForge could never be targeted; a door imported
  from someone else's `.map` could. Tie to Entity takes a name beside the class
  now, and Untie takes the name away with the class, or #620's dangling wire
  check would find a target that is ordinary geometry.
  Two brushes tied to one entity exported as two entities, because
  `entity_brush_blocks` held one entry per *node*: a door with two leaves
  compiled as two doors that moved independently. The export keys on the entity
  now. Not on `(class, name)` as the issue suggests, because that merges two
  separately tied unnamed doors into one: a tie mints a `brush_entity_group`, so
  identity is what the tie declared and the name is only the address a wire uses.
  The two are different questions and conflating them is wrong in both
  directions.
  The door was not a thing in the playtest scene. `_append_trigger_volume()`
  carries an entity's name, class and outputs onto the baked `Area3D`;
  `_append_detail_mesh()`, which is where a `func_door` goes because it is not a
  trigger, carried only the name -- so the runtime could find a node and nothing
  said what it was or what it was wired to. The two are symmetric now. A
  `Node3D` per entity is not needed for it: `HFIORuntime._cache_entity_under_key()`
  holds several nodes per name deliberately, so a two leaf door is two meshes
  answering to one name and both receive the input, which is what a two leaf door
  should do.
- **The entity classes the I/O system was built for** (#659). Three classes
  shipped -- a spawn, a point light and a door -- around a complete entity
  system: a schema-driven property editor, an I/O wiring panel with presets,
  a connection visualiser, a runtime dispatcher, `.map` entity export in both
  formats and the playtest exporter's mapping. All of it pointed at a light, a
  spawn and a door, so the gameplay half of the tool was unreachable without
  hand-authoring JSON first.
  `entities.json` ships fifteen now. The brush entities are `trigger_once`,
  `trigger_multiple`, `func_door`, `func_button`, `func_detail` and `func_wall` --
  the last two were already offered as hard coded fallbacks by the dock when the
  JSON had no brush entities at all, which was the shape of the same gap. The
  point entities gain `light_spot`, `light_directional`, `prop_static`,
  `info_target`, `logic_relay` and `logic_timer`. Each is a JSON object of the
  shape the existing three use, with `maps_to` on the light properties so they
  drive the real Godot node, so no code changes are implied by most of them.
  `door_basic` stays. It is a point entity with a box preview rather than the
  brush entity this lineage builds a door out of, but removing it would break
  every level already using one; `func_door` is the one to reach for now.
- **A prefab name cannot write outside the prefab directory** (#667). The library
  panel's Save box is free text and it went straight into a path.
  `to_snake_case()` normalises case and word breaks and does not touch a slash, a
  dot or a leading `..`, so `../escape` resolved to `res://escape.hfprefab` --
  sitting beside `project.godot`, outside the directory, and invisible to the
  panel that made it. `validate_filename()` is the engine's own rule for what a
  filesystem accepts and replaces every separator, but it is not enough on its
  own: `../escape` comes out of it as `.._escape`, which is safe from separators
  and still leads with a dot, so leading dots are stripped as well. Names are
  capped at 200 characters, and a name that cleans away to nothing becomes
  `untitled` -- trimmed *before* `to_snake_case()`, which turns a run of spaces
  into a run of underscores and so made `"   "` come out as `___`.
  `validate_filename()` also replaces characters a filesystem refuses without
  knowing about names it refuses: on Windows `CON`, `NUL`, `PRN`, `AUX` and the
  COM and LPT series are devices whatever extension follows, so `CON.hfprefab`
  could not be opened and the save failed with nothing on screen. Only the whole
  name is a device, so `console` and `aux_wall` are untouched.
  A save that genuinely fails now says so. `quick_save_prefab()` reported failure
  as an empty string and nothing above it turned that into a message, so a mapper
  whose disk was full got the same feedback as one who typed a slash: the name
  stayed in the box, the list did not change, and the button looked like it had
  not registered the click.
- **The prefab search filters instead of dimming** (#667). An `ItemList` has no
  per-item visibility, so the panel set non-matching rows to 15% alpha and
  disabled them: a search in a directory of fifty prefabs still showed fifty
  rows, and the mapper scrolled a list of unreadable text looking for the two
  that lit up. It rebuilds the list from the entries it found on disk now, the
  way the material browser rebuilds its grid, and `_file_paths` stays parallel to
  the rows that are actually visible so selection and drag follow the filter.
  A `.hfprefab` that will not parse is no longer offered as an ordinary prefab.
  `refresh()` listed by extension and added the row before the load below it had
  answered, so a file holding `this is not json` appeared with a normal name and
  could be dragged into a level. The parse result is available at that point, so
  such a file is marked and disabled -- visible, because it is on disk and the
  mapper should see it, and unusable, because it is not a prefab.
- **The distances #625 did not reach** (#658). One world unit is a metre since
  #625 -- the player is 1.6, a default drawn brush is 2, the grid snaps at 0.5
  and the shipped examples are 8 unit rooms -- and these are the numbers that
  conversion missed, where a value that used to be a small nudge became several
  rooms.
  **The Polygon tool** extruded to a literal 32.0, twenty players tall, and the
  literal appeared in the two resets as well: a mapper who dragged the height
  down to something usable got 32 back on the next polygon. It starts from the
  level's own `brush_size_default.y` now and then remembers whatever was last
  built, so the tool follows the project's scale and then the mapper's.
  **`door_basic.speed`** was 200 units a second. The playtest player walks at 6.5
  and a doorway is about 2 units across, so the door was open in ten
  milliseconds. It is 2.
  **Four dock controls** ran to sixty-four units, forty players, so every useful
  bevel radius sat in the first few percent of the slider with sixty units of
  dead travel after it and an arrow-key step sized for the range rather than the
  level. Bevel radius, inset distance and inset height now run to 4 with a 0.05
  step; the displacement paint radius runs to 8, because terrain covers more
  ground than a brush detail does. Their defaults moved with them -- a bevel
  radius of 2.0 on a 2 unit brush bevels the whole brush, so fixing only the
  range would have left the control unusable out of the box.
  The fifth control the sweep named, displacement elevation, is deliberately
  unchanged. The dock calls it a "Scale multiplier for displacement heights" and
  `HFDisplacementSystem.set_elevation()` is "Set elevation scale": it is
  unitless, so reading it as metres and dividing it by the 16 that #625 used
  elsewhere would have been a wrong answer confidently applied. The sweep's own
  check has been corrected to measure distances only.
- **The bake chunks on the path it actually takes** (#656). `_bake_impl()` picks
  between two geometry paths and only the CSG one had a chunked branch.
  `bake_use_face_materials` defaults to true, so on every default level the bake
  took the branch that had never heard of `bake_chunk_size` -- while the dock
  offered a Chunk Size spin, `get_level_health()` said "Consider Chunking"
  between 50 and 100 nodes, and `bake_dry_run()` reported a chunk count the bake
  did not produce. Twenty-five separated pillars at chunk size 8 promised 25
  chunks and made none, and the only way in was turning the default off.
  The per-face path groups per chunk now as well as per material.
  `collect_snapshot_groups()` fills a dictionary the caller hands it, so it takes
  one per chunk; the brush's world origin is already in the snapshot, taken
  before the yields, so partitioning needs nothing off the live node. Per-brush
  collision hulls and visgroup partitioning are sliced per chunk too, or a
  chunk's convex hulls would be built from the whole level's brushes. Chunks are
  emitted in a sorted order so two bakes of one level produce the same scene.
  A single chunk returns exactly what the unchunked path returned, with the same
  node shape, so nothing downstream has to learn about chunking to keep working;
  several are wrapped in `BakedChunk_` children the way the CSG path wraps them,
  which `postprocess_bake()` and the preview modes already walk. None of the
  CSG-boundary reasoning is needed here, because per-face baking has no boolean
  interactions to preserve across a boundary -- which is why
  `_chunking_has_cross_boundary_interactions()` guards the other path, and why
  `get_bake_chunk_count()` now asks which path will run before applying it.
  `bake_chunk_size` defaults to 0, meaning one mesh, rather than 32.0. That was
  a world-space number from before #625 made one unit one metre: four rooms wide
  on a project whose shipped examples are 8 unit rooms, so the whole of a greybox
  level fell in one chunk and the setting did nothing even on the path that could
  chunk. A fixed distance is the wrong kind of default for this, because it goes
  stale the moment the project's scale moves. `get_recommended_chunk_size()`
  returns 0.0 for anything under 30 brushes, so off agrees with the
  recommendation for every level small enough to want one mesh, and the status
  board already offers **Set chunk size N** once a level is large enough to want
  chunking.
- **The palette has a way back out** (#661). A fresh level's palette is empty, so
  **Refresh Prototypes** is the first button a mapper presses, and it adds 150
  materials in one go. The only way back was the minus button, 149 times, and
  each press walked every brush in the level and rebuilt every preview: 124 ms on
  a six brush room, O(removals x brushes) on a real one, assuming the mapper was
  willing to press a button 149 times to undo one press. The first thing a new
  user does was one-way.
  `remove_materials_from_palette()` takes a set. It builds one index map -- where
  each surviving slot lands, -1 for the ones going -- applies it in a single walk
  of the level and rebuilds the previews once, so the cost is the size of the
  level rather than the size of the removal. **Clear** and **Remove Unused** are
  one line each on top of it, and both are in the palette's button row beside the
  one that fills it. A face whose slot goes is unset rather than left dangling,
  and keeps its geometry.
  No Validate check for a mostly dead palette, which the issue floats: a palette
  with unused slots is the ordinary state while building, and Refresh Prototypes
  gives you 150 of them on purpose. The buttons report their count in a toast
  when pressed, which is the same information without the nagging.
- **Justify moves a hand-made UV layout instead of throwing it away** (#654).
  `justify_selected_faces()` reads a face's current UV rectangle out of
  `custom_uvs`, works out the shift that would put it where the button says, and
  then hands the face to `_justify_face()` -- every branch of which ends
  `face.custom_uvs = PackedVector2Array()`. Clearing it drops the face back to
  its projection, so the shift was applied to a rectangle it was not measured
  from: the mapper lost the hand alignment *and* did not get the button's result.
  Justify Left on a face dragged to `u[-3.75..4.25]` put its left edge at -4.25
  and stretched it to sixteen UV units wide. For a face nobody had hand-edited
  the two rectangles are the same one, which is why this never showed up, and the
  UV editor is the surface that writes `custom_uvs`, so the two texturing tools
  in the dock were silently undoing each other.
  `_justify_layout()` moves the layout instead: `custom_uvs` is per-vertex and in
  the same space the shift is measured in, so every mode is a scale and an offset
  over the points. `uv_offset` and `uv_scale` are left alone there, because the
  layout already carries the result and applying it to both would count it twice.
  A face with no layout still goes through the offset, so it stays free to
  re-project when its geometry changes rather than being pinned to explicit UVs.
  Which of the two a face gets is decided from whether it had `custom_uvs` before
  the selection was built, because both call sites run `ensure_custom_uvs()` to
  measure and that fills them from the projection.
- **Two pieces of code nothing could reach** (#654, #670). `_justify_face()`
  implemented a seventh mode, `stretch`, that no button and no console command
  could ask for and whose body was character for character the `fit` body above
  it. The viewport context menu carried a `_ID_APPLY_MATERIAL` const and a `match`
  arm turning it into an action string, with no `add_item()` anywhere -- and
  `apply_material` was the one action name in that file `HFPluginCommands.execute()`
  had no arm for, which is consistent: nothing could ask for it, so nothing had to
  handle it. Both are gone. The neighbouring `Apply to Whole Brush` entry is
  complete and unaffected.
- **Validate runs the checks that already existed** (#657, #666, #669). Three
  checks were implemented, working, and reachable from everywhere except the
  button a mapper presses before shipping. `validate_convexity()` gated the
  vertex tools; `validate_spawn()` sat 130 lines from the function that places
  the spawn; `check_missing_dependencies()` walked the material palette and
  nothing else.
  **Merge accepted brushes that do not touch** and collected their faces into one
  `DraftBrush`, so two cubes eight units apart became one brush made of two
  disconnected lumps -- which is not convex, and convexity is the one property a
  brush in this lineage has to have. The volume gave it away: two 2-unit cubes
  merged to 16, not the 40 a convex hull would be. Nothing downstream objected.
  Validate reported nothing, the `.map` export wrote twelve planes describing the
  intersection of two separate boxes, and the bake generated a convex collision
  hull spanning the whole 10-unit extent, so the gap between the pieces became
  solid to the player while staying empty to the eye. `can_merge_brushes()`
  refuses a selection that is not one connected lump, by world AABB closed
  transitively -- the same sweep `_chunking_has_cross_boundary_interactions()`
  does -- so a touching run of three still merges and two pillars across a room
  do not. `merge_brushes_by_ids()` already consulted the guard itself, which is
  the rule its own comment sets out. Validate runs `check_solid()` over every
  brush as well, because a non-convex brush can also arrive from a `.map` import
  or a hand edited `.tscn`, and there is no `auto_fix` for one: it is two solids
  or a bent one, and guessing which the mapper meant would throw geometry away.
  **The default spawn was placed above the ceiling.** `create_default_spawn()`
  used the centroid of the brush origins plus five units, with a hard coded
  `Vector3(0, 5, 0)` for an empty level. Five units was a small step up when a
  room was 256 units tall; since #625 the player is 1.6 and a room is 3, so it
  put the spawn above anything a mapper builds -- and `validate_spawn()`, further
  down the same file, rejected where it had just been put. It uses the level's
  own AABB now, standing on the floor with the same `height_offset` default that
  `entities.json` carries and `validate_spawn()` measures against, so the two
  agree. Validate gained a spawn check, deliberately geometric rather than
  calling `validate_spawn()`: that one raycasts, so it needs collision, and the
  collision comes from the bake -- `dock_manage_handler.gd` bakes before calling
  it for exactly that reason. Validate runs on an unbaked level, which is most
  levels most of the time, so asking the physics space would have reported "no
  floor below" for all of them, and a check that cries wolf is worse than the
  silence it replaced.
  **A prefab instance whose source file has gone** is a missing dependency now.
  The instance keeps working, because the brushes are real brushes, so nothing
  looked wrong until someone pressed Cycle Variant and got an empty string back
  or Propagate and got "0 instances updated". `validate_level()` already prefixes
  and reports whatever `check_missing_dependencies()` returns, so that was the
  whole change.
- **An undo puts the brushes back where they were, not at the end** (#660). Undo
  is a whole-level snapshot restore, and #600 made that affordable by keeping the
  brushes whose record still matches instead of rebuilding every one. A kept
  brush stays where it is in the container; a rebuilt one is `add_child`ed, so it
  lands at the back. The brushes a restore rebuilds are exactly the ones the
  undone action changed, so every undo moved the brushes the mapper had just
  touched to the end of the level, and `capture_state()` records the container in
  order. Capture, restore, capture therefore gave a different dictionary from
  capture -- the fixed point the whole undo design rests on, which nothing
  asserted. Over forty mixed edits undone one at a time, 37 of the 40 steps
  landed somewhere other than the snapshot they were given, with the same set of
  brushes in a different order.
  Two things follow from it. The `.tscn` and the `.hflevel` both serialise the
  brushes in container order, so a session where the mapper undid anything
  produced a diff even when the level ended up identical: review of a level file
  is useless and merges conflict on lines nobody touched. And brush order is CSG
  order -- `append_brush_list_to_csg()` adds children in order and a `SUBTRACT`
  brush only cuts what precedes it -- so on the CSG bake path a cutter an undo
  had moved to the end was a different boolean from the one that was set up. The
  per-face path is order independent, which is the only reason this was not
  already a visible geometry bug.
  `restore_state()` now walks the ordered `brushes` array it already holds and
  puts each node back at its index; anything the record does not name, such as a
  preview brush, keeps its relative order after the ones it does. The
  `id_counter` drift was the same defect in a field rather than a list: the
  counter was set from the snapshot *before* the rebuilds, and `_next_brush_id()`
  climbed it while they ran, so it ended one higher every time. It is set
  afterwards now. Ids carry a microsecond timestamp, so the counter is a suffix
  and putting it back cannot collide.
  A third cause, which the issue's own measurement showed without naming: the
  brush's node name. Godot auto-names an unnamed brush `@Node3D@14`, and that
  cannot round trip -- `@` is not a character a node name may hold, so setting it
  back gives `_Node3D_14`. Recording the sanitised form instead is not a fix
  either, because the engine reuses the number once a node is freed: over a long
  session one live brush is `@Node3D@14` while another is already `_Node3D_14`
  from an earlier restore, both record the same name, and the one that gets
  rebuilt collides with the one that survived and becomes `_Node3D_15`. A
  generated name is not identity -- `brush_id` is -- so it is no longer captured
  at all, and the engine keeps owning the names it makes up. An authored name,
  which is what entity I/O and the baked `Area3D` are named after, round-trips
  exactly as before.
  Together these make a save after an undo a no-op rather than a rewrite:
  `save_hflevel()` already skipped a payload whose hash matched the last one, and
  the payload now genuinely matches, so the write does not happen at all.
- **A `.map` keeps its texture names and its entity keys through a round trip**
  (#662, #663). `parse_map_text()` reads every key/value pair a block carries and
  every face's texture name. The level only took some of them, so ten brushes of
  a TrenchBroom file arrived with perfect geometry, sixty faces on slot -1, and
  an export that wrote `__default` sixty times. In this lineage a texture name is
  not decoration -- `AAATRIGGER` is a trigger volume, `*water1` is water, `sky1`
  is sky -- so dropping it drops the classification. The mechanism was all there:
  the importer already built `map_textures`, and `_apply_map_textures()` already
  mapped a name to a palette slot. It opened with `if palette.is_empty(): return`,
  and a fresh import is into an empty palette, so it gave up on exactly the path
  it existed for. The name now goes on the face whatever the palette holds, as
  `FaceData.map_texture`, which makes the round trip lossless in a project with
  no materials loaded at all; a name the palette does not have mints a
  placeholder slot named after it, carrying no resource path because a `.map`
  names a texture without saying where it lives.
  The same shape on the keys. A point entity's survived, because it was the only
  kind of block that reached the branch that stored them. A brush entity's were
  read and discarded, so a `func_door` arrived in the right place, with the right
  name, and no `speed`, `wait` or `angle` -- a door that does not move. They ride
  on a `brush_entity_data` meta now, through the same info-to-meta path the class
  and the name already used. `worldspawn`'s were discarded too, because it has
  brushes and so never reached that branch at all: an exported map had no `wad`
  to compile its textures against and no `message` to name it. They live on
  `LevelRoot.map_worldspawn_properties`, travel in the `.hflevel`, and are
  written back above the world brushes. That is also the first home the editor
  has had for a level name.
  `target`/`targetname` is kept as an ordinary property rather than translated
  into HammerForge's own I/O. The reverse mapping is not one-to-one and deserves
  its own decision; keeping the pair is what stops a round trip destroying the
  only logic a three entity map has.
- **A level autosaves to its own file** (#655). `hflevel_autosave_path` shipped
  as one literal, `res://.hammerforge/autosave.hflevel`, with autosave already
  on and a five minute timer. So every level in a project pointed at the same
  file, and nothing unusual had to happen: open `e1m1`, build, leave it; open
  `e1m2`, build for five minutes; `e1m1`'s `.hflevel` is now `e1m2`. The mapper
  found out on reopening the first level, by which time the rotation in
  `.hammerforge/` held five copies of the wrong one, and `load_hflevel()` had
  reported success the whole way because the file it read was perfectly valid.
  #618 fixed the neighbouring half of this by keying the backup rotation per
  level; the path that rotation is keyed on was still one path for everybody.
  A level already knows where it lives, so `resolved_hflevel_path()` derives the
  default from `scene_source_path()` instead, mirroring the scene's whole path
  under `res://`: `res://levels/e1m1.tscn` autosaves to
  `res://.hammerforge/levels/e1m1.hflevel`. The whole path rather than the
  basename, because `levels/test.tscn` beside `prototypes/test.tscn` is an
  ordinary way to end up in a project and the basename alone would have put
  those two back on one file. A level given its own path from the dialog keeps
  it, and no existing level's stored value changes. Every reader goes through
  it, including the backup rotation, the freshness check, the status board and
  the console, so the board now names the file a level is actually writing to
  rather than the one they all claimed.
  A scene that has never been saved has no name to derive from, and that is the
  case where the autosave is the *only* copy of the work, so it is the worst
  version of this rather than an edge of it. Such a level mints a `level_uid`
  once, kept in the scene, and autosaves to `unsaved_<uid>.hflevel` until it has
  a `.tscn` to be named after.
  The collision is still reachable by pointing two levels at one path by hand,
  so the file's own record of where it came from (#646) is now a guard as well as
  a report: an autosave whose target `.hflevel` names a different scene is
  refused, and says so once rather than every five minutes. A file that records
  no scene is not refused on a guess, and neither is **Save Level** -- writing
  over another level's file on purpose is a thing a mapper is allowed to do.
  It mattered most for a `SceneContents.BAKE_ONLY` level, where the `.hflevel`
  is the only copy of the brushes and the shared path meant the level could
  silently open as a different one.
- **Ctrl+S keeps the records that describe the brushes, not only the brushes**
  (#664, #665). A level has two saves. `capture_state()` writes the `.hflevel`
  and carries everything; Godot's own Ctrl+S writes the `.tscn`, which is
  `PackedScene.pack()` over the nodes. Visgroups, groups, arrays, hollows,
  generators and prefab instances are not nodes -- each lives on a `RefCounted`
  subsystem -- so the scene save wrote all eighteen brushes of a furnished level
  and none of the five registries that could still edit them. A spiral stair
  whose step count the mapper was promised they could change came back as loose
  geometry; `update_hollow()` had no record to re-shell; the array controls went
  dead with nothing to follow. Worse for visgroups, where membership *is* node
  metadata and always survived: a visgroup hidden at save time reopened with its
  brushes invisible, still claiming to belong to a group the dock had never heard
  of, and no control anywhere that could show them. `LevelRoot.live_registries`
  is an `@export_storage` dictionary holding exactly what `pack()` drops.
  Computed on read rather than kept in step, because the value has to be current
  at the instant something packs the scene and no one notification covers every
  packer -- the editor's save, a tool script and the exploratory harness each
  reach `pack()` by a different route. It is filled and emptied by
  `capture_registries()`/`restore_registries()`, split out of `capture_state()`
  so the two saves share one definition and a record added later reaches both or
  neither. Scenes already saved without the list are repaired rather than left
  broken: every node carrying a `visgroups` meta names a visgroup that should
  exist, so `reconcile_visgroups_from_members()` puts it back on open. A
  recovered visgroup is visible, because the flag is not recoverable from the
  members and that is the direction that does not leave geometry unreachable.
  Two more things the same save dropped for their own reasons. A paint layer is
  a node and the scene always wrote it, but `layers` was an index built only by
  `create_layer()`, so a reopened level had every layer node present, an empty
  index, and a second `layer_0` added on top of the one `_ready()` could not
  see -- and the layer nodes had no `owner`, which is what decides whether
  `pack()` walks past a node at all. And a face's surface paint came back empty
  with `Attempted to assign an object into a TypedArray` on the console:
  `FaceData.PaintLayer` was an inner class, which has no type a `.tscn` can
  name, so the scene wrote the layers and the engine refused them on load. It is
  `HFFacePaintLayer` in its own file now, still reachable as
  `FaceData.PaintLayer` through a const preload, so no call site changed.
- **A visgroup can be renamed, a prefab variant deleted, a displacement's power
  changed** (#615). Three level-editing operations were implemented, carefully,
  and had no entry point outside the GUT suite. Each was the missing half of a
  feature whose other half was already in the dock, and each left the mapper
  doing destructive busywork instead. `rename_visgroup()` carried a collision
  check and a rewrite of every member's metadata, and the dock could create a
  visgroup, delete one, add and remove a selection and toggle visibility, but not
  rename, so someone who named one `roof` and later wanted `roof_upper` had to
  make a new one, re-add every member and delete the old. There is a **Rename**
  button beside **Delete** now, and a name that is already taken is refused rather
  than merging two visgroups, because merging is a different operation. The
  prefab library could add a variant, show a `[N variants]` indicator and cycle
  through them with Ctrl+Shift+V, so the list was append-only while the file's own
  header comment said the context menu could delete one; **Remove Variant** is on
  that menu now and does not offer `base`. And the **Power** spin was read once,
  at creation, so its tooltip described a choice that was final: a cliff sculpted
  at 9x9 could only reach 17x17 through Destroy and Create, which throws the
  sculpt away. `set_power()` resamples the old grid into the new one and was
  written for exactly this, and an **Apply** button beside the spin now calls it.
  The user guide already claimed that last one worked, which is the shape of all
  three: the feature was finished everywhere except where someone could reach it.
- **Undo keeps the brushes it would have rebuilt identically** (#600). Undo and
  redo are whole-level snapshots, so the price of taking back a one-brush nudge
  was set by the size of the level rather than the size of the edit: at 400
  brushes an undo step was 141 ms, of which `restore_state()` was 122 ms, because
  it cleared the level and recreated every brush node. Twenty-two of the
  twenty-three top-level keys in a snapshot are untouched by a brush move, and
  inside the one that did change, 399 of 400 brush records are identical too. A
  brush whose record is identical to what it would capture right now is the brush
  that record describes, so `clear_brushes()` now takes a set of ids to leave
  alone and those brushes are registered again rather than freed and rebuilt.
  Restore at 400 brushes went from 122 ms to 44 ms, and what is left is mostly
  the comparison, which is the same walk the capture already does. A brush that
  fails the comparison is rebuilt exactly as before, so a comparison that says no
  when it could have said yes costs time and nothing else; there is no way for it
  to say yes wrongly, because two brushes with identical records are identical to
  anything that reads a record, and undo has always been exactly that. The
  comparison is `recursive_equal()` rather than `==`, because a record carries its
  faces as an array of dictionaries and `==` does not go down into those. The
  snapshot is still a whole-level snapshot and still costs what it costs to take;
  this is the half that was rebuilding what nobody changed.
- **The threaded `.hflevel` save does its serializing on the thread** (#601). The
  write was threaded and the work in front of it was not, so two thirds of a save
  happened on the calling thread. Autosave runs on a timer nobody chose the
  moment of, which made it a stall the editor took on its own schedule: 183 ms at
  400 brushes, growing linearly. `capture_hflevel_state()` did two things, and
  only one of them had to be here. Walking the scene does, and so does reading a
  `resource_path` off a material the editor owns. Turning Vector3s and
  Transform3Ds into arrays does not, and that was 128 ms of the 147 ms.
  `capture_hflevel_payload()` now stops after the walk, with the Resources
  resolved in place so the payload that crosses to the worker holds nothing but
  values, and `encode_variant()` runs on the worker. The blocking half of a
  400-brush save went from 183 ms to 55 ms, and 25 brushes went from 12 ms to
  4 ms. The deep copy went with it: `save_hflevel()` used to `duplicate(true)`
  the structure it had just been handed, which was 13 ms and a doubling of peak
  memory to protect it from nobody, because nothing else held a reference. A live
  `Array[Material]` cannot have a Dictionary written into it, so an array
  declared to hold objects is rebuilt rather than written through, which is what
  the suite checks: the payload is asserted to hold no Resource at all rather
  than the list of places one can appear being trusted, because that list grows
  every time the format does.
- **A paint layer's chunk size can no longer change out from under its own
  chunks** (#625). Convert to Heightmap built the layer, filled every cell, and
  then set `chunk_size` from the manager. A chunk allocates its bit, material and
  blend arrays for the size it was built at, while `_cell_to_local()` reduces a
  cell against the layer's current `chunk_size`, so once the two disagreed every
  read indexed past the end of a `PackedByteArray`. That is an engine error, not
  something the layer can report. It had never fired because a test brush fitted
  inside one cell at the old 16 unit grid; at one unit to the metre the same
  brush spans eight cells and the convert threw on the first read. The conversion
  now takes the chunk size as a setting and applies it before the first cell, and
  the layer refuses a change once it holds paint rather than accepting one it
  cannot honour. Every other caller already set it on a fresh layer.
- **An occluder is the wall it stands for, not every wall on its plane**
  (#614). `_generate_occluders()` grouped triangles by normal and plane distance
  and nothing else, so two triangles facing the same way in the same infinite
  plane went into one occluder whether they shared an edge or were a level
  apart. In a grid-snapped greybox that is constantly: every floor at y = 0,
  every wall on the same line. Godot gives an `OccluderInstance3D` a single
  bounding volume, so the result was an occluder the size of the level, never
  culled itself, considered from every camera position, standing for a surface
  that was mostly holes. Forty boxes in a row measured one occluder spanning all
  10,113 units between the first and the last, and the span grew with the level.
  Triangles are now grouped into flat surfaces: coplanar **and** touching, tested
  on welded vertex positions, which is what sharing an edge comes to for baked
  geometry. One wall is one occluder; two walls a room apart are two. Two brushes
  that abut without sharing vertices give two occluders rather than one, which is
  the right answer either way round. The old merge was also a scan of every plane
  found so far for every triangle, which is quadratic in the triangle count; the
  new grouping is a single pass keyed on vertex position, because each vertex
  already names the handful of triangles that meet there. `Min Area` now measures
  a surface rather than a plane, so scattered fragments that used to reach the
  threshold by pooling across the level are skipped, which is what the threshold
  was for.
- **A prefab keeps its materials in another level** (#621). A face's material is
  a slot number into the *level's* palette, and a `.hfprefab` carried the number
  without the palette. Every reuse silently re-textured: a doorframe built out of
  blue checker arrived purple hex, and a prefab built against an eight-slot
  palette left every face above the destination's last slot pointing out of
  range. It worked inside one level, because the palette is the same one, so it
  was invisible until the first time anyone did the thing prefabs exist for. The
  capture now records the `resource_path` each referenced slot pointed at, and
  placement resolves those against the destination palette - appending what it
  does not already hold, keyed on path so placing the same prefab twice does not
  add the material twice - and rewrites the face indices to match. The append
  lands inside the existing undo pair, because the placement takes its before and
  after state around `instantiate()` and `capture_state()` carries the palette. A
  material with no `resource_path` still cannot be recorded, which is #617 from
  the other side; its slot is left alone rather than recorded as something the
  load cannot resolve. A recorded path the project cannot load is reported by
  name instead of silently re-texturing. A `.hfprefab` written before this block
  existed has none and is placed exactly as it was.
- **The shortcut dialog can be opened, and custom tools survive an upgrade**
  (#606, #612). `HFShortcutDialog` is a searchable, categorised keyboard
  reference, and the only thing referencing it was a handler nothing called, so
  the user guide told mappers twice to press a **?** button that did not exist -
  and the binding-conflict warning the dialog is the only home for was
  unreachable with it. The button is now on the dock toolbar beside **More** and
  **Help**. Separately, the only place the plugin looked for a custom tool was
  `res://addons/hammerforge/tools/`, which is the folder the upgrade
  instructions tell you to replace, so every tool a project wrote was destroyed
  by the documented upgrade with no error - and the directory was not in the
  repository at all, so `load_external_tools()` returned on its first line every
  launch and the advertised extension point could not be found. Tools now go in
  `res://hammerforge_tools/`, outside the addon, the way `HFEntityDef` already
  looks for `res://hammerforge_entities.json`. The folder ships with a README and
  a complete example tool under `examples/`, which the non-recursive scan
  deliberately does not register. The in-addon path is still scanned so an
  existing install loses nothing, and `hammerforge_tools/` is now covered by
  gdformat and gdlint in CI.
- **Two bake switches that produced nothing now produce something, or say why**
  (#611, #623). **Generate LODs** reached the baker intact and came back with no
  levels, because `generate_lods()` builds LOD *index* arrays by simplifying an
  indexed surface and the CSG merge path hands over a triangle soup - every
  corner a loose vertex, no indices. The face-material path already welded its
  surfaces for exactly this reason; the other one did not. `_mesh_with_lods()`
  now indexes first, which also shrinks the mesh on its own, and leaves an
  already-indexed surface untouched so nothing that worked goes through
  `SurfaceTool` twice. **Use atlas** was the harder one: the packer is correct
  and the exclusion is correct too - an atlas rect cannot repeat, so a face whose
  UVs leave the unit square cannot be atlased - but HammerForge maps world units
  into UV space, so an ordinary 64-unit face is 0..64 and every group is
  excluded. On a level built with the defaults the switch packs nothing, and
  nothing anywhere distinguished that from having worked. The pass now reports
  what it did, the way the occluder and auto-connector passes do: `Atlas: packed
  4 of 6 material groups into one atlas`, or `Atlas: skipped, 6 of 6 material
  groups have tiling UVs` with the warning that puts it in the Console Log.
- **The door stops previewing as a light bulb, and an entity class says what it
  fires** (#613). `door_basic` pointed its mesh preview at
  `light_bulb_proxy.obj`, which is the only file in the plugin's `meshes/`
  folder, so a level with doors and lights in it showed a bulb for both kinds of
  thing with a different tint. Previews now understand a `box` type - a sized
  `BoxMesh` with no asset behind it - and the door uses it. The other half is the
  vocabulary: `entities.json` shipped three entries, none declaring any I/O
  names, while the wiring system, the six built-in presets and the overlay's
  colour table all assumed `OnTrigger`, `OnPressed`, `Open`, `Toggle`, `TurnOn`
  and the rest. A definition can now declare `outputs` and `inputs`, the three
  built-ins do, and the quick-wire form offers them in a dropdown beside each
  box - the source's outputs in **Out**, the chosen target's inputs in **In**.
  The boxes stay free text, because a mapper may wire to a name no definition
  declares; what changes is that the names are discoverable from the entity
  instead of only from the presets.
- **The Objects tab lists an entity's connections once** (#616). It built two
  lists of the same wiring, one above the other, and refreshed both for the same
  selection. The two label builders were the same code twice and had already
  drifted, so one connection appeared as `OnPressed -> door_1.Open [once]` and
  again as the same line ending `[1x]`. Only the plainer list could be acted on:
  the wiring panel's own list was built, cleared, filled and its selection never
  read, so the surface the user guide describes at length and a mapper actually
  works in was the one where you could not delete a wire. **Remove Output** now
  sits on the wiring panel beside the list it acts on, and `io_list`,
  `io_remove_btn` and `refresh_io_list()` are gone. One connection, one line of
  text, built in one place.
- **An entity definition now becomes the node it names** (#598, #599). Every
  entity in `entities.json` declares a `class`, and the user guide documented it
  as the Godot node class the entity stands for. Nothing instantiated it: the
  parser read that field only as a name, and because the JSON key was injected as
  `id` first, `light_point`'s `"OmniLight3D"` was never read at all. Placing a
  light gave you a billboard in the editor and a bare `Node3D` at runtime, so
  every Test Level looked the same - one hard-coded `PlaytestSun` - and moving a
  light or changing its Range changed nothing. The optional `scene` field had the
  same shape one level up: parsed, round-tripped through `to_dict()`, and never
  loaded. A playtest export now builds the scene or the class the definition
  names, applies the authored property values, and carries the entity's name,
  wiring and other metadata onto it. The three `light_point` properties were also
  not `OmniLight3D` property names, so a new optional `maps_to` key says which
  engine property a declared property writes to; `range` reaches `omni_range`.
  A missing scene or a class this build cannot make warns and exports the marker,
  so a wrong definition never costs you the level. `from_dict()` now prefers
  `classname` over `class`, without which a definition naming a node class could
  not survive its own round trip.
- **A broken I/O wire is now visible on all three surfaces that should show it**
  (#602, #603, #620). Wiring is held by name, and renaming a target is the most
  ordinary way it breaks. Nothing noticed. The overlay resolved each connection
  and skipped the ones it could not, so the broken wire was the invisible one and
  a level whose wiring was entirely broken drew as a level with no wiring at all;
  a dangling output is now drawn as a short red mast with a cross on top, rising
  from the source. `validate_level()` walked every output and never asked whether
  anything answered to the target; it now resolves each one against
  `build_name_index()` and names the wire it could not resolve. And
  `get_connection_summary()` used `if`/`elif` on one connection record, so an
  entity wired to itself satisfied the first branch and was never counted among
  what triggers it - the surface a mapper uses to answer "what fires this?" said
  nothing did. The two tests are independent questions and are both `if` now.
- **Autosaving one level no longer deletes another level's backups** (#618).
  `_write_autosave_rotation()` named each history file after the level that wrote
  it and then called a prune that forgot the name: every `.hflevel` in
  `autosave_history/` was a candidate, sorted by modification time, with
  everything past the keep count deleted. Two levels in one project share the
  folder and so shared one budget, and the budget was spent on whichever level
  saved last - three autosaves of a second level was enough to wipe the first
  level's history. The prune now takes the base name and only considers that
  level's files, checking that what follows the name looks like a timestamp so
  `level` does not prune `level_backup`. The timestamp itself was only to the
  second, and `write_bytes_atomic()` replaces rather than refuses, so three saves
  inside one second left one backup; it now carries milliseconds and refuses to
  land on a path that already exists.
- **A setting's declared range is now the range it is held to** (#622, #607).
  `@export_range` is the Inspector's spinner and nothing else, so four
  properties on `LevelRoot` took whatever a script, a `.hflevel` settings block
  or an undo replay gave them: `bake_collision_layer_index`,
  `draft_pick_layer_index` and `grid_major_line_frequency` all kept 100000, and
  `hflevel_autosave_minutes` was clamped at the bottom only. That last one had a
  live consequence - an interval above 60 set a timer measured in weeks, so the
  autosave toggle still read as enabled and nothing ever saved. All four now
  clamp in their setter against named `MIN_*`/`MAX_*` constants, the way #373
  left the rest of the file. The Console's Chunk size row hard-coded a maximum
  of 256 against the dock's 16384; because the Console writes through the dock's
  own spin, touching that row dragged a legal chunk size down to 256 and wrote it
  back to the level. It now reads `LevelRoot.MAX_BAKE_CHUNK_SIZE`, which is where
  the bound was already written down.
- **A round brush now lands inside the rectangle that was dragged** (#604, #605).
  For a cylinder, cone or sphere the base rectangle was squared off the *longer*
  side and then anchored at the drag origin, so a 128 x 32 drag produced a brush
  128 deep - four times the ground the rectangle enclosed and 96 units past where
  the drag stopped. There was no drag at all that produced a cylinder the size of
  a narrow rectangle. The smaller side is now the diameter and the footprint is
  centred on the rectangle, so a mapper dragging up to a wall or between two
  pillars gets a brush that fits. The second stage of a sphere drag was tracked,
  snapped, shown in the HUD and then discarded; `SPHERE` is uniform by
  definition - `ELLIPSOID` is the shape with three independent axes - so the
  height now takes part in the diameter and a shorter drag makes a smaller ball.
  Resize handles are unchanged: either radial handle still drives the shared X/Z
  radius, which is the behaviour the user guide already describes. The Build tab
  section of the user guide now states the rule the drag follows.
- **The `.hflevel` writer no longer loses a value without saying so** (#619,
  #617). `encode_variant()` named the handful of types it knew and passed
  everything else to `JSON.stringify`, which turned nine Variant types into
  strings that no later read could turn back - `Vector2i`, `Vector3i`, `Vector4`,
  `Rect2`, `Rect2i`, `AABB`, `Plane`, `Quaternion`, `Transform2D`, the packed
  arrays and `StringName`. A dictionary key was copied rather than encoded, so a
  `Vector2i` cell key came back as the string `"(3, 4)"`. Both now round trip:
  the remaining types go through `JSON.from_native()`, the engine's own JSON
  representation for them, and a dictionary with any non-String key is written as
  a list of encoded pairs. `to_native()` is called with `allow_objects` false,
  because a level file is untrusted input. Anything genuinely unwritable - an
  `Object`, `RID`, `Callable` or `Signal` - now warns instead of producing a
  string. A `Resource` with no `resource_path` was written as a bare `null`; it
  now warns on save and records the class and name, so the load can say what the
  empty slot used to be rather than leaving the reader to guess, which is the
  resolution `save_library()` already had (#515). The format version is not
  bumped: every shape an old file holds decodes exactly as it did, and the new
  envelopes only appear where the old encoder wrote garbage. The hand-flattened
  cordon AABB in `hf_state_system.gd` and the hand-converted paint blend arrays
  are left alone - they are the shape on disk now - but the comment saying why
  is no longer missing.
- **Undoing a brush resize no longer renames every brush in the level** (#597).
  `restore_state()` clears the brushes and rebuilds them from their captured
  info, and the node name was the one thing that info never carried. So a resize
  followed by Ctrl+Z brought `Floor` and `Wall` back as `@Node3D@27719` and
  `@Node3D@27718`. Geometry, ids, faces, visgroups and entity wiring all
  survived; only the names died, and not just on the brush that was resized -
  on every brush, because the restore rebuilds all of them. That is worse than
  cosmetic. An entity I/O output targets a brush by name, and the baked `Area3D`
  takes its name from it, so an undo quietly unwired every connection in the
  level with no error and no warning. Entity infos have carried their node name
  all along; brushes were the odd one out, and now match. Found by running the
  release gate's resize-handle check for the first time (#593).
- **Clicking a brush in the 3D viewport no longer throws you onto the HammerForge
  main screen** (#592). Nothing in the plugin asked for the switch. Godot's
  `EditorData::get_handling_main_editor()` hands the main screen to any plugin
  that both declares one and handles the selected object, walking the plugin list
  backwards so an addon beats the built-in 3D editor. HammerForge declared a main
  screen for the switcher icon and separately answered `_handles()` true for
  `LevelRoot`, `DraftBrush` and `DraftEntity`, and the pair is what Godot switched
  on. `_handles()` is now permanently false, which is the shape the Godot main
  screen tutorial documents. Nothing is lost: viewport input comes from the
  force-forwarding lists set in `_enter_tree()`, not from handled objects, and the
  only other thing `_handles()` bought was `_edit()` setting `active_root`. That
  moved to `sync_active_root_from_selection()` off `selection_changed`, gated by
  the same `should_handle_editor_object()` bar, so a camera still cannot steal the
  sticky root. The rule now sits beside `_has_main_screen()` and in
  `DEVELOPMENT.md`, because the two halves were each correct on their own and the
  next person will otherwise put them back together.

### Removed
- **The visgroup colour** (#551). A visgroup carried one from the moment it was
  created, it was serialised into the `.hflevel` and read back out, and it had a
  setter - and nothing anywhere read one. No `get_visgroup_color()`, no swatch in
  the Manage tab, no gizmo or overlay tinting by it, and no caller for
  `set_visgroup_color()` in `addons/`, `tests/` or `tools/`. The only reads were
  the two inside the serialiser, writing the value it had been handed back out
  again. Every visgroup in practice was `Color.WHITE`, because the one caller that
  creates them never passed a colour. Colour-coded visgroups are worth having -
  seeing which brushes are the lights and which are the detail is the point of
  visgroups on a large level - but what was there was the cost of that feature
  with the value of neither, so it is a feature to open on its own terms rather
  than a field to keep carrying into every save and every undo snapshot.
  `restore_visgroups()` reads past a `color` key in an older payload.
- **Nineteen public functions with no call site** (#572). A scan over `addons/`,
  `tests/` and `tools/` with comments stripped first, so a name mentioned in
  prose did not count as a use. Half were named `LevelRoot` delegates, which this
  project's own rule keeps only where something calls them by name.
  `paint_displacement()` and `set_displacement_power()` went together - the
  displacement input path reaches `root.displacement_system.paint()` directly.
  The two the issue flagged for a look first both checked out:
  `HFSnapSystem.clear_geometry_cache()` is genuinely unnecessary, because a cache
  entry is validated against the brush's `instance_id`, `face_count` and `size`,
  and a state restore frees the old brushes so their entries no longer match; and
  nothing in `addons/` reads `HFTerrainRegionManager.dirty_regions` at all, so
  `clear_dirty()` was not the missing half of an eviction - the set it clears is
  itself written and never read.
- **`Dock.set_status_grid()`, `set_status_mode()` and `set_show_hud()`** (#555).
  `set_status_grid()` was the worst: a doc comment saying "Update the grid
  display in the status bar", a parameter that is never read, and a guard around
  a `pass`. Anyone wiring grid snap to the status bar would have found it, called
  it, and got nothing. `set_status_mode()` read as the simple case of
  `set_mode_indicator()` sitting immediately below it and was the superseded one;
  `_update_mode_indicator()` went with it, having lost its only caller.
- **`autosave_interval` and `last_tool_id` from the preferences schema** (#568).
  Both typed, defaulted, validated on load and written to `user://` on every
  save, and read by nothing. `autosave_interval` was the one that misled: there
  are two autosave-interval settings in the plugin, and the one that works is
  `hflevel_autosave_minutes` on `LevelRoot`, with a spin and a Console row - so
  anyone finding this one in the prefs file and editing it got no effect and no
  message. `_validated()` keeps a key it does not know, so an existing prefs file
  carrying either is not warned about. Removing both leaves no `TYPE_INT`
  preference in the schema, so the int half of `_usable()`'s number coercion is
  now there for the next one rather than exercised by a test.
- **`HFPaintTool.material_picked`** (#553). Declared, emitted on every Ctrl+Click
  on the floor paint grid, and connected by nothing. One correction to the
  issue's reading: the gesture is not inert. `pick_cell_material()` sets
  `blend_material_id`, which is what the next blend stroke writes, and
  `plugin_paint_input.gd` already toasts "Picked floor material N" - so the
  eyedropper lands and says so, and it was only the signal that stopped at the
  boundary. It has nowhere useful to go either: the picked id is a terrain slot
  rather than a palette index, so there is no material browser selection for it
  to move. The `return true` stays, because the pick is a real gesture rather
  than a swallowed click.
- **`HFPrefabLibrary.set_prefab_dir()`** (#556). `res://prefabs` was written out
  three times - the library, `HFPrefabSystem` and `dock.gd` - and the setter
  could only change one of them, so calling it would have left the library
  listing a different folder from the one Save writes into and the one `dock.gd`
  scans. A setter that moves one of three copies of a constant is worse than no
  setter, because it looks like the supported way. There is one
  `HFPrefabSystem.PREFAB_DIR` now that all three read, and the directory is
  honestly a constant. Making it configurable is a prefs key and a real setter
  behind that one value, which is a change worth making deliberately.
- **`HFGesture`** (#550). A `class_name`, a doc comment describing an
  architecture where "the plugin holds at most one active gesture" and routes all
  input through it, and 109 lines nothing constructs - no subclass, no `new()`,
  no preload anywhere in `addons/`, `tests/` or `tools/`.
  `HFSelectionGesture` sounds like one and is not. The expensive part was the
  complete numeric-entry mechanism inside it, reimplemented separately in
  `plugin_numeric_input.gd`, which is the copy that runs: the dead one still has
  the keypad-Enter bug frozen into it that #516 and #517 fixed, so it was a
  second and wrong reference for anyone who found it first. The guide's Gesture
  Tracker section goes with it; if the architecture is still wanted it is a
  design question against what `HFSelectionGesture`, `HFPluginGestureRecovery`
  and `input_state.gd` actually do.
- **`HFFoliagePopulator`** (#562). 146 lines, documented in two guides as a
  shipped subsystem, constructed by nothing. The Paint tab's Foliage & Scatter
  section commits through `HFScatterBrush`, which is a superset - the same
  `density`, `min_height`, `max_height`, `max_slope` and the identical
  `_compute_slope()`, plus a density preview, a circle and a spline shape, an
  instance budget with a refusal message, and a `rejected_count`. The dead copy
  was also the weaker one: no budget, so `populate()` built a `Transform3D` per
  instance over every cell of every chunk with nothing capping the total, which
  is the shape #512 was about. The greybox guide's section is now about
  `HFScatterBrush`, which does everything it claimed and more, and
  `hf_scatter_brush.gd` no longer says it works with a class that is gone.
- **The state system's transaction API** (#571). `begin_transaction()`,
  `commit_transaction()`, `rollback_transaction()`, `is_in_transaction()` and
  their three fields, called by nothing and not covered by the GUT suite, while
  `HammerForge_MVP_GUIDE.md` listed them as a shipped capability. Every
  multi-step operation that wanted this solved it separately -
  `_commit_state_action()` through `HFUndoHelper`, the generator's hand-rolled
  appearance capture, `propagate_from_source()` with no grouping at all - so the
  designed answer was not serving as the answer. Grouping a propagate into one
  undo step is worth doing; it is worth doing against a design rather than by
  finding four functions nobody has used. `LevelRoot.discard_signal_batch()`
  stays: it was the transaction's only caller, but it is the one way to abandon
  an open signal batch, `begin_signal_batch()` has live callers, and
  `test_dirty_tags.gd` covers its behaviour.
- **The per-instance prefab override mechanism** (#566). A record field, three
  public functions, a re-apply pass, the overlay's override markers and a
  `capture_state()` field, with no way in: nothing outside
  `tests/test_prefab_enhancements.gd` ever called `set_override()`, so an
  override could not be created, seen or cleared from inside HammerForge. It was
  not finished underneath either - the only brush case it handled wrote a
  `brush_size` meta, which the overlay reads for its own bounding box and nothing
  reads to resize a brush, so applying a size override did not resize anything;
  `_apply_variant()` never re-applied them, so a variant cycle would have dropped
  every one; and only two of the field paths it accepted did anything at all. The
  `capture_state()` field is the part that mattered: the shape of those paths was
  a file-format commitment already made by a mechanism nobody had used.
  `restore_state()` reads past an `overrides` key in an older payload.
  Per-instance overrides are worth having and worth designing - the way in is the
  open question, not the storage - so that is an issue to open on its own terms.
  `compute_instance_diff()` stays: its two remaining comparisons are brush and
  entity counts, which do not depend on overrides.
- **`BrushInstance.selected_faces`, and the pass that maintained it** (#563). The
  field was written for every brush on every face-selection change and read by
  nothing - not `rebuild_preview()`, not `_build_face_preview()`, not the gizmo
  plugin. The selection highlight is drawn from `LevelRoot.face_selection`, which
  is also what `capture_state()` carries and what `face_selection_changed`
  announces, so that is the one copy. The cost was real:
  `HFBrushSystem._apply_face_selection()` called `set_selected_faces()` on every
  brush in the level on every click in face mode, and `set_selected_faces()` ends
  in `rebuild_preview()` - a full preview rebuild per brush per click, for a value
  that changed nothing on screen. `HFPaintSystem.apply_face_selection()` was a
  third copy of the same loop with no caller at all.
- **Five fields that were assigned and never read** (#564).
  `HFFileSystem._last_write_error` was the misleading one: it recorded exactly
  what a reader chasing "why did my save fail" would want, and nothing consumed
  it - the real route is the `hflevel_save_failed` signal and the
  `_completed_saves` queue. Checked before removing it that nothing reaches it
  alone: the worker always returns a Dictionary, which lands in `_completed_saves`
  and reaches the signal, so no save failure went unreported.
  `HFSubtractPreview._csg_result_count` was set to the same value as
  `_active_count` at every one of its four sites, so there was no rebuild guard to
  restore. `HFBakeSystem._last_dirty_brush_ids` carried a comment describing when
  it was captured, which is a promise about how it is used.
  `HFExampleLibrary._selected_id` and `HFStatusRow._theme_source` round it out -
  both of the latter's writers already have `base_control` in hand and pass it
  straight through.
- **Five signals that were declared and never emitted** (#521).
  `HFContextToolbar.tool_switch_requested` and `hotkey_palette_requested` had
  connect and disconnect pairs in `plugin.gd` and a real handler on the other
  end, for commands nothing in the viewport could ask for. Both commands are
  reachable elsewhere - the palette through `dock.command_palette_requested`,
  tool switching from the Build tab and the shortcuts - so the signals and the
  four plugin lines are gone rather than the toolbar gaining buttons nobody asked
  for; `_on_context_tool_switch()` went with them, having lost its only caller.
  `HFPaintLayer.layer_changed` and `HFIOWiringPanel.connection_removed` had no
  connect either. `LevelRoot.selection_changed` is the fifth, found by the new
  check: the dock connected it and its handler only called
  `_sync_surface_paint_from_root()`, which `face_selection_changed` already
  triggers and does emit.
- **`InferenceSettings.angle_snap_degrees`** (#520). Read by nothing, promised by
  no doc, and not something this pass does: `infer_intent()` classifies a stroke
  and `apply_cleanup()` edits cells, and neither has an angle in it.
- **The material usage tracker** (#375). `record_usage()`, `release_usage()`,
  `rebuild_usage()`, `find_unused_materials()` and `get_usage_count()` had no
  caller anywhere — not the dock, not the plugin, not the state system, not the
  test suite — and `rebuild_usage()` counted the wrong thing: it read
  `child.material_override`, which is the draft preview tint the brush system
  sets for operation colouring, rather than `FaceData.material_idx`, which is
  what the Paint tab writes, what the `.hflevel` stores and what the bake reads.
  A level whose every face was painted with a material reported that material as
  unused. Nothing could go wrong today because nothing called it; the risk was
  the next person to want "find unused materials" finding five ready-made
  functions with plausible names and wiring them up to a "Remove unused" button
  that would strip the palette of materials in use.

### Changed
- **The Floor Paint inference settings are bools with honest names** (#520).
  `denoise_min_island_area`, `fill_max_hole_area`, `gap_tolerance` and
  `min_corridor_width` were all read as on/off thresholds, so 5 did exactly what
  1 did and 50 did exactly what 2 did. The one-cell bound is deliberate and the
  class comment defends it; the names were what was wrong, and a settings panel
  built from them would have been four spin boxes that only switch. They are
  `denoise`, `fill_holes`, `fill_gaps` and `widen_corridors` now. The engine is
  still opt-in and unwired, so nothing shipped changes behaviour.
- **A vertex move that bends a face now splits it instead of being refused.**
  A brush face is a plane and every face of a box is a quad, so moving one of
  its four corners bends it. #364 made that a refusal, which is correct but
  means no single corner of a box can be dragged at all. On commit each bent
  face is now cut into triangles along the same fan the bake already uses, so
  the committed surface is the one that was on screen during the drag, and each
  triangle keeps its quad's material and projection. Hand-placed UVs on a split
  face go back to the face projection, because four of them do not describe
  three vertices. A move that dents the brush is still refused: no
  triangulation of a bent face makes a concave solid convex, and with the quad
  in two pieces the dent is finally something the convexity check can see. The
  refusal now lands on release rather than mid-drag. A bent face carrying a
  displacement is also still refused, because the displacement is defined over
  four corners and a split would throw it away. The face count goes up under
  the mapper, which is the part of this that had to be decided rather than
  fall out of a missing check.

### Fixed
- **The tool registry asks `can_activate()` before activating** (#552).
  `HFEditorTool` documents a two-part poll - `can_activate()` and
  `get_poll_fail_reason()`, the string written to explain precisely this - and
  neither had a call site anywhere. `HFDecalTool` and `HFMeasureTool` both
  override `can_activate()` and both overrides were dead, so pressing N or M with
  no LevelRoot in the scene made the tool active, the toolbar showed it as
  active, and every click did nothing. It matters more for the extension point:
  `load_external_tools()` scans a directory and the contract that scan advertises
  includes these two methods, so a third-party tool needing a face selected had
  one documented way to say so and it was not consulted. The refusal is reported
  the way the tool wrote it. Same function and the same failure shape as #508.
- **A custom tool's declared settings produce controls** (#554).
  `rebuild_tool_settings()` was about ninety lines handling the whole declared
  type set, and its own doc comment said it was "called when an external tool is
  activated via the registry" - it was called by nothing, and
  `_on_tool_setting_changed()` and `_clear_tool_settings()` were reachable only
  from it. `get_settings_schema()` is the one documented way a custom tool
  exposes anything adjustable and `set_setting()` had no other route from the UI,
  so a tool author declaring a radius and a mode got no panel at all - and #509's
  fix to `set_setting()` had no live caller. `activate_tool()` takes a settings
  callback in the same shape as the undo and history ones it already takes, and
  the dock builds the panel into a **Tool Settings** section on the Build tab,
  hidden while the active tool declares none.
- **Auto connector mode's stairs-vs-ramp threshold is a setting** (#570). The
  Connector Mode tooltip has always told the mapper a threshold decides it, and
  there was nowhere to look: `stair_threshold` was a constant on
  `HFAutoConnector.Settings` with no `LevelRoot` property, no control, nothing in
  the bake settings list and nothing in the `.hflevel` - while the two connector
  numbers beside it on the same row both had all four. It has them now.
  The default moves from 2.0 to 32.0 at the same time: 2.0 is a small height at
  this genre's scale, so on a level built at 32-unit grid steps every cross-layer
  boundary cleared it, Auto was Stairs everywhere, and the ramp half of the mode
  never happened. The tooltip names the control rather than an unreachable
  number.
- **Material browser favourites survive the dock being rebuilt** (#545).
  `_favorites` was a plain Dictionary on the control with nothing reading it out
  or writing it in - no prefs key, nothing in the `.hflevel`, nothing in
  `capture_state()` - and the dock builds the browser fresh, so every star was
  gone at the next theme change, project reload or editor restart, with the
  Favorites view and the HUD's favourites row coming up empty and nothing to say
  why. They are kept in `HFUserPrefs` by resource path now, which is what the
  other settings that outlive a level already do, and the dock hands them back
  every time it refreshes the browser.
- **Starring one unsaved material no longer stars every unsaved material**
  (#544). Favourites are keyed on `resource_path`, and a material built in the
  editor session has an empty one - so every unsaved material in the palette
  shared one key. One star lit the lot, and un-starring any one of them cleared
  them all, which is the normal state of a palette being built up before anything
  is written to disk. `add_favorite()` refuses an empty path and returns whether
  it took, so the dock can say "Save the material to disk before starring it"
  rather than doing something surprising. Paths rather than palette indices for
  the reason the issue gives: an index is only stable while the palette is, and
  this outlives the level.
- **A radial array about an axis index that does not exist is refused** (#541).
  `axis_vector()` and `rotation_basis()` both fall through to Z, so a ring about
  axis 7 or axis -1 was built about Z, climbed along Z and reported as a success -
  and the saved array record then said axis 3 while the brushes said Z.
  `HFTransformSystem.is_valid_axis()` exists for exactly this and says so in its
  own comment; `radial_placements()` was the one caller of `axis_vector()` that
  skipped it. `can_generate()` refuses the same index, so the gate says "that is
  not an axis" rather than the layout quietly coming back empty.
- **`grid_placements()` refuses a count below one, the way `grid_copy_count()`
  already did** (#542). There were two ways to ask how many copies a grid makes
  and they disagreed: the dock measured through `placements_for()` and got 3 for
  counts of (0, 2, 2), the brush system measured through `grid_copy_count()` and
  got -1, and both fed the same `can_generate()` gate. The clamp that
  `grid_copy_count()`'s own comment says was removed was still in the other half
  of the pair, so down the dock path a zero or a minus sign became "a plausible
  array they never described" - the precise outcome that comment says was fixed.
- **One `axis_vector()`, and the clip paths use its guard** (#567).
  `HFConvexClip.axis_normal()` was a byte-identical second copy with no guard
  beside it, so a fix to either was not a fix to the other - and #541 was the
  same fall-through in a third place. It calls `HFTransformSystem.axis_vector()`
  now. `clip_brush_by_id()` and `can_clip_brush()` clamped the index rather than
  falling through, which is the same silent wrong answer wearing a different hat:
  5 became a cut on Z and -1 a cut on X, reported on the axis it picked. Both
  refuse now, so the ghost and the operation still agree.
- **Validate + Fix reports what is left, not what it repaired** (#569). The
  handler threw away the `fixed` count `validate_level(true)` returns and
  re-derived it by differencing two more full validation passes - which is not
  the number of repairs, since a pass that fixes one issue and exposes another
  reported zero fixed - and then logged the issue list from *before* the fix, so
  every problem it had just repaired was printed as though it were still there,
  with no list of what remained. It reads the validator's own count now and
  re-runs once for the residue, which is what the log prints; the status line
  reads "fixed N, M remaining", and a level that comes out clean says so. Three
  passes become two, and the second is needed because `validate()` reports every
  finding whether or not it repaired it. `HFUndoHelper.commit_completed()` is new:
  `commit()` calls the method itself and discards the return, so a caller that
  needs it could not use it.
- **The Status board's recommended chunk size is one the editor can accept**
  (#549). `get_recommended_chunk_size()` has no ceiling and the dock spin it is
  written through had a maximum of 256, so for any level wider than 1024 units -
  small, in this genre - the level got 256 and the Log tab was told the
  unclamped number. The line exists so the action is auditable, and it disagreed
  with the level. The Console reads the value back after assigning it, the way
  `dock.gd`'s bake path already does, and the spin's maximum is now
  `LevelRoot.MAX_BAKE_CHUNK_SIZE` rather than a smaller number of its own - so
  the recommendation the perf panel shows is one the control beside it can hold.
- **The Log tab says how much the buffer actually holds** (#543). Trimming is
  amortised in batches of `TRIM_SLACK`, so `capacity` is what the buffer trims
  down to rather than a ceiling it never passes - the buffer sits anywhere
  between 600 and 663 at the default. The footer reported `capacity`, which is
  the one place a reader is told what the limit is. It says "holds up to" and the
  real figure now, via `retained_limit()`; the amortisation is worth keeping, so
  it is the reported number that was wrong.
- **Cycling a prefab variant leaves the instance where it was** (#565). A
  prefab's brush transforms are stored relative to the merged visual AABB centre
  of the selection it was captured from, and `instantiate()` adds the placement
  back onto that. `_apply_variant()` re-placed the instance at the mean of the
  node origins instead, which is a different point for any prefab that is not
  symmetric about it - so every press of Cycle Variant walked the instance by the
  difference, and recomputed it against the new nodes, so cycling back did not
  bring it home. A door frame or a crate stack is exactly the asymmetric case;
  everything the same size happened to work. One definition now, the one the file
  format is written against, and `set_variant()` takes the same path.
- **A chord built on a tool shortcut key is no longer that tool** (#574).
  `HFToolRegistry.check_shortcut()` matched the bare keycode and never looked at
  modifiers, so Ctrl+M, Alt+M and Ctrl+Alt+M all activated Measure, and so did
  Shift+M in paint mode, where the flip family is gated off and the event fell
  through to the tool check at the end of the router. Activating a tool is not a
  quiet no-op: Measure and Decal take the viewport's left click, so a mis-struck
  Ctrl+M swapped the mapper out of Draw and the next click placed a ruler point.
  A tool shortcut is a bare key by construction - `tool_shortcut_key()` returns
  one keycode and has nowhere to say otherwise - so the check now refuses any
  modifier.
- **Save Prefab and Cycle Variant go through the keymap** (#575). Both were
  matched against raw keycodes in `plugin_input_router.gd`, so neither had an
  entry in `HFKeymap`, a row in the shortcut dialog or the hotkey palette, or any
  way to be rebound - while the context toolbar button beside the viewport named
  the chord. They were also invisible to the dialog's collision checking, so
  rebinding anything onto Ctrl+Shift+P reported no conflict and then lost to the
  hard-coded branch. `quick_save_prefab` and `cycle_variant` are keymap actions
  now, with labels, on the same defaults.
- **The context toolbar reads the keymap it is given** (#560). `_keymap` was
  assigned by `set_keymap()` and never read, while twenty-eight chords were
  written into the button tooltips as literals - so rebinding Hollow left the
  toolbar saying Ctrl+H forever, on the surface closest to the mapper's hand.
  The tooltips are `{action}` tokens rendered through `format_chords()` now, the
  way the HUD, the coach marks and the dock tooltips already were, and each
  button keeps its source line so a rebind re-renders it.
  `tests/test_shortcut_surfaces.gd` covers the toolbar as a fourth surface; it
  was missed the first time because that file named the other three.
- **Load Material Library and the two terrain slot commands register an undo
  step** (#573). All three change state `capture_state()` already carries, and
  none of them went through `_commit_state_action()` the way their forty
  neighbours do. Load Library is the one that cost: every face's `material_idx`
  is an index into the palette it replaces, so loading a different library
  repaints every painted face in the level, and Ctrl+Z stepped past it to
  whatever happened before the load - with no route back, since the old palette
  was only ever in memory. `LevelRoot.load_material_library()`,
  `set_terrain_slot_texture()` and `set_terrain_slot_uv_scale()` are what the
  wrappers name. The slot pair also gave the paint layer setters for arrays the
  dock had been writing into directly, which was the only place in the plugin
  that wrote a layer's arrays from outside the layer and the reason nothing
  bounded the slot index.
- **Inference cleanup leaves a one-cell stroke alone** (#546). Denoise removes a
  filled cell with no cardinal neighbour, and a single click on empty ground is
  exactly that - so with `Inference cleanup` ticked, clicking once painted
  nothing, with no warning and no undo step to show anything had happened. The
  pass runs on the stroke that was just made, so the one thing it was guaranteed
  to reach was what the mapper had just drawn. A stroke of one cell is skipped
  now; a stray cell in a larger stroke is still removed.
- **A one-cell dab is not a closed room** (#547). `HFStroke.analyse()` set
  `is_closed` from the distance between the first cell and the last, and for a
  stroke of one cell those are the same cell, so the distance was zero and a
  single click classified as a room whose outline had been drawn. A loop needs
  three cells to be one. `infer_intent()` also gained a note that `avg_speed` is
  part of the corridor test, so the same long thin run classifies as a corridor
  when it is drawn quickly and a blob when it is drawn slowly.
- **Reconciling one floor paint layer no longer deletes every other layer's
  geometry in the same chunk** (#561). `HFGeneratedReconciler.reconcile()` swept
  by chunk, and every layer shares one `Generated/Floors` and one
  `Generated/Walls`, so the pass for a layer freed the nodes belonging to all the
  others that touched the same chunk. `HFPaintSystem._reconcile_dirty_chunks()`
  runs that once per layer, so each pass undid the one before it and only the
  layer reconciled last had any geometry at all. A ground floor blinked out of
  existence whenever the walkway above it was painted, and a bake in between
  shipped a level missing a floor. Generated nodes now carry an `hf_layer` meta
  and the sweep only indexes the layer it was given; the id comes from the
  caller, so nothing depends on parsing it back out. A node left by an older
  build has no meta and is matched by its id instead.
- **A layer id is run through `validate_node_name()` before it is stored**
  (#548). The id sits in the middle of every generated brush id -
  `hf:floor:v1:<layer_id>:<chunk>:...` - and `chunk_tag_from_id()` reads field 4,
  so a ":" in the layer id shifted every field along and the reconciler read the
  wrong one as the chunk tag. A node whose tag matched no chunk in scope was left
  out of the index, so the reconciler rebuilt it and never swept the original:
  duplicated floor and wall geometry that no stroke removed. Plugin-minted ids
  are `layer_N` and could not do this; a `.hflevel` from another tool could, and
  `load_paint_layers()` took the id verbatim. `create_layer()` is the one funnel
  for every id, and the engine's own node-name rule is the right test, since the
  other characters it rejects were what made `Layer_a_b_c` and `a:b:c` disagree.
- **A whole-tree check that every signal the addon declares is emitted** (#521).
  A grep over `addons/hammerforge/`, the way `test_suite_integrity.gd` checks
  that every test script loads. It covers `name.emit(`, `emit_signal("name")` and
  the forwarding helpers the subsystems use, with a left word boundary so
  `layer_changed.emit(` is not matched inside `paint_layer_changed.emit(`. It
  found one more than the issue did.
- **`tools/` is format checked and linted in CI** (#500). Sixty-six `.gd` files -
  the vibe harness, its scenarios, the benchmark scripts, the showcase builder
  and the editor smoke setup - sat outside both checks and had drifted. One
  scenario carried a raw newline inside a double quoted string, which Godot's own
  parser takes and gdtoolkit does not, so the scenario ran while any other tool
  that reads GDScript choked on the file. That is #115 again, in the directory
  #115 never looked at. Both CI invocations cover `tools/` now and the eleven
  files that needed reformatting are reformatted; `gdlint` needed no rule relaxed.
- **The README At a Glance test count is maintained by the tool that measures it**
  (#502). `tools/update_test_counts.py` owned five sentences, and the At a Glance
  cell was a sixth number in a file it already rewrites. So CI corrected the badge
  at the top of the README on every wave and walked past the table two screens
  below it, which had read 2,860 since it was written - undercounting the suite by
  about a quarter, in the second thing a visitor reads. The cell is in `rewrites()`
  now, anchored on the prose around the number the way the other five are, and the
  commit step already had `README.md` in scope.
- **Save Preset no longer names two presets the same thing** (#513).
  `_suggest_preset_name()` counted the buttons on screen, which matches the
  highest name in use only until one is deleted. Three saves, delete the middle
  one, two more saves, and two buttons read "Preset 3".
  `_unique_preset_path()` made the file unique and left `resource_name` alone,
  and the label comes from `resource_name`, so the file was fine and the label
  was not - and the label is the only thing telling two presets apart in the
  Build tab. The suggestion now skips the names already on screen.
- **A `.hflevel` from a newer build is refused rather than half-read** (#499).
  Every bundle carried a format version and nothing read it. Defaulting a missing
  key protects new code reading old files; it does nothing for old code reading
  new ones, which is the case a version number exists for, and the first format
  change that is not purely additive would have been the one to find out - by
  which point `restore_state()` has already cleared the open level and restored
  whatever it could parse. `load_hflevel()` now reads the version before applying
  anything and refuses a bundle stamped higher than this build reads, reporting
  it the way a bad state is already reported. A missing or zero version is an
  older file and still loads. `HFLevelIO.FORMAT_VERSION` is the one place to bump
  it. The editor settings export and the terrain region sidecar write the same
  unread stamp and are left alone; they are separate files with separate readers.
- **Save Library and Load Library are in the Paint tab** (#498, #515). The User
  Guide has listed them under Material Library as if they were buttons since
  before either was reachable: `MaterialManager.save_library()` had no caller
  anywhere and `load_library()` had none outside a test. Both are wired into the
  Materials section beside Refresh Prototypes now, through the same file dialog
  pattern the rest of the dock uses, and the status line reports what the save
  could not record and what the load could not resolve.
  `save_library()` was the silent half of that pair (#515): a library records
  each slot's `resource_path`, a material made in the editor session has none, so
  a palette of four saved as four empty strings and reported `OK` while the load
  side restored four nulls and warned about every one of them. It warns on the
  way out now, names the slots through `get_dropped_save_slots()`, and returns
  `ERR_SKIP` when the file it just wrote restores nothing. Both functions close
  their `FileAccess`, which neither did.
  The User Guide, `features.md`, the data portability notes and the MVP guide are
  corrected: two of them still advertised the usage tracking #375 removed.
- **Editing a brush entity's metadata now marks the bake stale** (#510).
  `HFBrushChangeTracker._signature()` hashed the transform, visibility, size,
  shape, operation, sides, material override and every `FaceData`, and none of
  the node metadata. Three keys in there decide what a brush becomes in the bake:
  `brush_entity_class`, `entity_name` and `entity_io_outputs`. Godot 4's
  Inspector has a Metadata section that edits exactly those, which is the ground
  this tracker exists to cover, so all three could be changed with Bake Changed
  reporting nothing to do - the level looking right while the baked output still
  had the brush as plain world geometry, or wired to a target that no longer
  exists. All three are hashed now, with the outputs deep copied so an edit to a
  connection in place is not made underneath the snapshot.
- **A cylinder exports at the resolution it is drawn at** (#495).
  `_cylinder_to_map_lines()` set its side count with `max(6, brush.sides)`, while
  the viewport and the bake both use `DraftBrush.round_sides()`. The default
  cylinder has `sides` 4, which resolves to 16 on screen and was written out as a
  hexagon, and a 5 the brush explicitly supports was clamped to 6. The exported
  prism was not the shape the mapper saw, and `_face_for_normal()` then matched 6
  wall normals against 16 authored faces, so the face textures landed on the
  wrong walls.
- **`test_brush_shape_defaults` no longer leaks a CSG cylinder** (#496). The node
  built to compare the preview against the bake was never tracked or freed, so
  the suite exited with an orphan and a leaked RID, which is noise that hides the
  next real leak.
- **An entity input now reaches a handler whatever arity that handler has**
  (#497). `_deliver_to_target()` picked the call shape from the parameter string
  rather than from the method it was about to call, so a handler declared with no
  argument fired with a parameter raised a script error and was not called, and
  so did one requiring an argument fired without a parameter. Both are free text
  from a dock field with nothing checking that they agree. Worse, the error
  aborted delivery where it stood, so the snake_case name, `_on_io_input` and the
  user signal - the three fallbacks that exist so an input always lands
  somewhere - never ran. The shape is read off the target now. A handler needing
  two or more arguments cannot be satisfied from one parameter field, so it is
  skipped with a warning and the fallback chain runs. The reason this never
  failed a test is that every handler in the fixture was declared with a default,
  which accepts both call shapes.
- **The UV editor panel now shows the face it is given** (#506). It treated a
  face's UVs as a 0..1 fraction of the control, and a HammerForge UV is a world
  coordinate: `_project_uvs_for_vertices()` reads `Vector2(v.x, v.y)` off the
  vertex, so a 64 unit box face spans 64 and was drawn 64 canvases away. The
  panel was blank and inert on every brush, at every size, and read as "no face
  selected" rather than as a panel that does not work. Its one interaction made
  it worse: a drag clamped the dragged point into 0..1 while the other three
  stayed out at 32, so the face's UV quad stopped being a quad. The canvas is
  fitted to the face's own UV bounding box in `set_face()` and mapped through in
  both directions, with a margin so the outermost points are grabbable, and a
  drag is held to the canvas rect in screen space rather than to a UV range that
  was never the face's. A face with no span in one axis - a CYLINDRICAL
  projection, or any zero-area UV span - gets a fallback extent so the division
  is safe.
- **Convert to Heightmap now has a ceiling, and its remove-sources setting does
  what it says** (#511, #512). The grid was the selection's extent divided by the
  level's grid snap, with nothing capping the result - a number set for an
  unrelated reason, how far a brush moves when it is dragged, quietly deciding
  the resolution of an allocation that grows quadratically. A 512 unit brush at a
  snap of 0.1 is a 5124 x 5124 grid, about 210 MB across the float array and the
  image, walked twice on the main thread with no progress and no way to stop. The
  cell size now widens to keep the grid inside 2048 a side, the result carries
  the cell size it actually used, and the dock says so rather than leaving the
  mapper to wonder. `Image.create()` is checked for null. `remove_sources` was
  declared, documented on the class and asserted for its default by a test, and
  read by nothing; it removes the brushes it rasterised now, through the brush
  system so their cross references go with them, and the dock takes its undo
  snapshot before the convert rather than after so there is something to put
  back.
- **A dimension typed during a draw drag now shows on the brush, and keeps the
  drag's direction** (#516, #517). `update_preview()` wrote the typed value into
  the drag state and then called `update_drag()`, which recomputed the same field
  from the cursor. The number went onto the HUD and the brush under it carried
  on following the mouse, so the feature read as broken right up until it was
  committed. `HFInputState` carries a `numeric_override` now, which the drag
  system checks before it recomputes either field, and which is cleared when the
  buffer empties or the gesture ends. The typed base also kept the sign it never
  had: one number went onto X and Z as a positive extent, so a drag heading into
  negative X and Z - half of all drags - jumped to the opposite quadrant on
  Enter, with the HUD reading the same either way because
  `get_drag_dimensions()` takes `absf()`. The extent is built along the direction
  the drag already has, and positive when there is no direction yet.
- **The custom tool extension point no longer constructs what it is going to
  refuse** (#507, #508, #509). `load_external_tools()` called `.new()` on every
  `.gd` file in the scanned directory and checked what it got afterwards, so a
  file that is not a tool was constructed anyway: a `Node` subclass became an
  orphan for the life of the editor session, a script whose `_init()` takes
  arguments was a hard error, and one with side effects in `_init()` got them.
  The base script chain is walked instead, which answers the question without
  running any of the file, and a rejection is logged rather than skipped in
  silence. `activate_tool()` looked the id up after deactivating the tool in
  hand, so an id that is not registered turned the mapper's tool off and said
  nothing; it returns early with a warning now. `HFEditorTool.set_setting()`
  clamped `float` and `int` and let an `enum` through unchecked, so a tool
  indexed its own options array with a number the dock cannot show; an enum is
  held to its `options` the way a number is held to its min and max.
- **A generator setting is now held to both ends of its range, and to its own
  options** (#518, #519). `check_ranges()` tested a field's `max` and had no
  branch for `min`, and it skipped enum fields outright. Four fields across the
  four builders built real geometry out of range as a result: a staircase with
  zero-thickness treads, which is invisible edge-on and a surface the player
  falls through once it is baked to collision, and three structures started
  outside a full turn, which the dock then cannot express or edit back. An enum
  took any integer, so `stairs.fill` accepted 7 of its 2 choices. Both are
  checked now, with an enum's `options` array read as the range it is; an enum
  declaring no options is refused too, since the dock builds an empty
  OptionButton from one. A `.hflevel` carrying a value outside a bound now
  reports it instead of building from it.
- **A brush entity now answers to the name it was given** (#493). A brush tied
  to `func_door` or `func_button` keeps its authored name in metadata, because
  its node name is whatever Godot generated. `find_entities_by_name()` and
  `build_name_index()` compared the node name only, so an output aimed at a door
  never resolved and fell through to the fallback dispatch, and
  `unique_authored_name()` handed out names already taken by a brush entity.
  Both resolve against either address now, the way `_another_node_answers_to()`
  always has. The validator's duplicate-name and broken-connection checks walked
  `entities_node` alone and now walk the brush entities too, since a brush entity
  carries both a name and its own outputs.
- **The default bake path now runs the same finishing pass as the CSG one**
  (#494). `build_mesh_from_groups()` unwrapped UV0 and stopped there, so since
  #491 made `bake_use_face_materials` the default, every ordinary bake dropped
  the LODs and the lightmap UV2 the Bake Options asked for. It calls
  `_postprocess_mesh()` now, with `generate_lods`, `unwrap_uv2`, `uv2_texel_size`
  and `unwrap_uv0` from the options. The face surfaces are also welded into an
  index array on the way out: Godot generates LODs off the indices, so wiring the
  pass in on its own would have fixed the UV2 half and left the LOD half exactly
  as it was.
- **A new level no longer fails its own validator** (#514). The rule paired
  `bake_use_face_materials` with an empty palette, which was a deliberate
  combination when face materials were off by default and is the ordinary
  starting state now that they are on. Every untouched level reported an issue,
  which is how a validator loses the weight it needs. It now warns only when some
  face actually points at a palette slot, which is the case where the bake
  produces untextured geometry the mapper did not ask for.
- **The UV tail of an exported `.map` face line is now in the units a `.map`
  uses** (#503, #504, #505). Three numbers close every face line and all three
  were wrong. The rotation went out in radians into a field that means degrees,
  so a face turned 45 degrees was written as `0.7854` and arrived turned by less
  than one degree. The scale went out uninverted: `_apply_uv_transform()`
  multiplies a world coordinate by `uv_scale` and a `.map` reader divides by the
  scale field, so the same number meant twice the repeats inside HammerForge and
  half of them in the file, and nudging the dock to correct an export made it
  worse. A `uv_scale` of zero went out as a texture scale of zero, which is a
  divide by zero in every Quake family compiler. `HFMapAdapter` now owns the
  conversion for both formats: degrees out, the reciprocal scale out, and 1
  substituted for a zero or non-finite scale with one warning per export naming
  the brushes. A negative scale stays negative, because that is how a mirrored
  face is written and `adjust_uvs_for_rotation()` produces one deliberately.
  `uv_offset` is unchanged and now says why in a comment: with the scale written
  as its reciprocal the two offsets are the same quantity.
- **Every dock command that changes the level now registers an undo step**
  (#470, #471, #472, #473, #474, #475). Thirteen of them called `level_root`
  directly: New, Add Sel, Rem Sel and Delete on the visgroup list, Group and
  Ungroup, Create Entity, Add and Remove on the entity I/O list, Add Layer and
  Remove Layer, Generate Noise and Import Heightmap. Ctrl+Z after any of them
  undid whatever
  came before instead, so a misclick on Delete Visgroup lost the membership of
  every brush in it and the keystroke that should have taken it back removed
  something else. Group and Ungroup were the worst of the set because they
  recorded a row in the History panel, which is where a mapper looks to see what
  can be stepped back. All of them go through `_commit_state_action()` now, and
  the History panel entry comes from the same wrapper. Convert to Heightmap
  builds its layer inline, so it registers the work it already did.
  `capture_state()` already carried the visgroups, the groups, the entities and
  the paint layers; nothing about the data was in the way.
- **A redo no longer reaches for a node the undo freed.** `restore_state()`
  clears the brushes and entities and rebuilds them from their captured info, so
  a command registered with a live node in its arguments had a dangling
  reference waiting in the redo. `_commit_state_action()` takes an
  `absolute_redo` flag for those, which registers the resulting state as the do
  operation instead of the call. Every command above that takes a selection or
  an entity uses it.
- **The wiring panel's connections and presets are undoable** (#473). The panel
  holds the entity system rather than the dock's undo manager, so it could not
  register its own step. It now says when it is about to change something, the
  dock takes the before state, and the done signal commits the pair - which
  matters most for a preset, where the alternative to one Ctrl+Z was deleting a
  dozen connections by hand. A preset that applies nothing says so, rather than
  leaving a before state to pair with whatever happened next.
- **Add Sel leaves the visgroup row it just used selected** (#476). All three
  visgroup commands end in `refresh_visgroup_ui()`, which clears the ItemList
  and rebuilds it, so the highlight was gone and the next Add Sel, Rem Sel or
  Delete was a silent no-op until the mapper clicked the visgroup again - which
  dropped every click after the first in the natural workflow. The row goes back
  after the refresh, the way the visibility toggle on the same list already did
  it, and a command that finds no visgroup highlighted now says so.
- **The live auto-connector path costs the stroke instead of the level**
  (#441). `defs_for_touched_cells()` is documented as the cheap path that "does
  not scan or rebuild geometry", and its first statement was a full
  `detect_boundaries()` - which walks every cell of every chunk of every layer
  to build a dictionary from scratch, then compares each filled cell against
  every other layer. The touched-cell filter ran afterwards, on the result, so
  the cheap path cost the same as the scan it claimed to avoid and grew with
  the size of the level rather than the size of the stroke: 39 ms per committed
  stroke on a level with 8,192 painted cells, while dragging. The live path now
  walks the touched cells and their four neighbours directly, and a test
  asserts it gives the same answer as filtering the full scan so the two cannot
  drift apart.
- **Import Settings validates what it reads instead of casting it** (#478). The
  parsed `.hfsettings` dictionary went into the level through bare `float()`,
  `int()` and `bool()` calls. `float("sixteen")` is `0.0` in GDScript, so a
  hand-edited file, or one from a writer that quotes its numbers, turned
  snapping off in silence; `int({})` raises at the cast, so a value of the wrong
  container type aborted the rest of the block rather than being reported. All
  26 reads go through validating readers now, which keep the setting in force
  and name the key that was refused, in the shape `HFUserPrefs` got in #423.
  `_apply_grid_snap()` also writes the value the SpinBox ended up holding rather
  than the one it was handed, so an imported 4096 no longer leaves the dock
  reading 128 while the level snaps to 4096 and the out-of-range number goes
  into the prefs file to come back next session.
- **Import Settings writes the connector mode to the level** (#477).
  `OptionButton.select()` does not emit `item_selected`, and that signal was the
  only thing that wrote `bake_connector_mode`. The dropdown said Auto and the
  bake ran Ramp, with nothing to say which was in force, until the mapper
  happened to touch the dropdown or reselect the LevelRoot - which made the
  wrong state come and go. The import goes through a `_select_option_notifying()`
  helper now, so the one place that knows what to write is still the only place
  that writes it. A test pins the `select()` behaviour, because the class
  reference does not state it.
- **`bake_collision_mode` and `bake_connector_mode` clamp to the modes that
  exist** (#480). #373 gave the unbounded bake and grid settings clamping
  setters and missed the two whose legal values are an enum rather than a range.
  `bake_connector_mode` had no setter at all, and `@export_range` is an
  inspector hint that does not clamp an assignment from code, so both took
  anything a `.hflevel` settings block or a settings import handed them. Both
  are read as a mode with `match` or index arithmetic at bake time, so an
  out-of-range value baked as whichever branch the default happened to be and
  the level baked differently from what its own file said.
- **A bake chunk size of 0 is the "off" the bake already understands** (#481).
  `bake()` reads `if root.bake_chunk_size > 0.0` and 0 is the bottom of the dock
  spin's own range, but the property clamped it up to `MIN_BAKE_CHUNK_SIZE`.
  Turning the spin all the way down gave the opposite of what it said: one-unit
  chunks, which is the finest chunking the editor can do and the slowest bake
  available, where the mapper had asked for none. A negative value means off as
  well, for the same reason - clamping it up to 1 was the worst answer on offer.
  Import Settings also reads the chunk size once and lets the spin clamp it,
  rather than reading it twice with different fallbacks, which could leave the
  spin and the level saying different things about the chunking.
- **The HUD, the coach marks and the tooltips read the keymap instead of
  spelling chords out** (#439, #440). `HFKeymap` is rebindable, and three of the
  surfaces that tell a mapper which key does what held their chords as string
  literals: 14 in `shortcut_hud.gd`, 6 in `hf_coach_marks.gd`, 5 in
  `hf_tooltip_text.gd`. After one rebind the same editor showed the new chord in
  the hotkey palette and the old one in the viewport HUD, the coach marks and
  the tooltip - and the HUD is the one on screen while the mapper is working.
  Nothing checked them against the defaults either, so changing a default left
  three files behind with no error. Each surface now writes `{hollow}` and a new
  `HFKeymap.format_chords()` renders it, with a test that every token names an
  action the keymap knows and that no rebindable chord is written out. The
  rebind list also showed two rows called "Extrude Up" and two called "Extrude
  Down", because `get_action_label()` gave the same name to an action and its
  alias; the aliases are named as aliases now.
- **A surface paint stroke lands where the cursor is** (#464). `pick_face()`
  reports the face's own UV, and a face's UVs are the projection of its world
  coordinates, so a 128-unit wall spans 128 in U rather than 1.
  `paint_surface_at()` clamped that to 0..1, which threw the position away: every
  stroke on a face larger than one unit landed in one of two corners of the
  weight image, chosen by the sign of the coordinate. The painted albedo becomes
  the material's `albedo_texture` and is sampled through those same UVs, so the
  texel under the cursor is the one the fractional part points at, and that is
  what the stroke uses now. The brush also wraps at the tile edges rather than
  being cut in half there, and a radius wider than half the image is capped so it
  cannot wrap onto itself and paint the same texel twice in one sample. The mask
  still repeats with the texture it sits in; making it span the face instead is a
  change to how a painted face is sampled, not to where a stroke goes.
- **A surface paint sample walks the circle instead of its bounding square**
  (#465). `paint_at_uv()` scanned a square of `(2r+1)^2` texels and threw away
  the corners one at a time, and built a `range()` array for every row of it - at
  the top of the dock's radius range, 257 arrays of 257 ints per sample, on the
  main thread, for every mouse-motion event while the button is held. It now
  takes each row's own span from one `sqrt` a row, and skips a contribution too
  small to change an 8-bit channel. Measured on the vibe `surface-paint`
  scenario: 52 ms a sample before, about 17 ms after. The `PackedByteArray`
  rewrite that usually goes with this was not done, because it is measured about
  seven times *slower* than `get_pixel` in this engine - see
  `tools/benchmark_paint_hot_paths.gd`. Memoising the falloff was tried and
  reverted: it bought 3%, because what is left is the per-texel `Image` calls
  rather than the arithmetic.
- **Per-face materials reach the baked mesh** (#466). The bake has two paths: the
  face-material path triangulates each face and resolves its own material, and
  the CSG path does not. Which one runs was decided by
  `bake_use_face_materials`, which defaulted to false, with the check box that
  mirrors it unticked inside the Advanced fold of the Test tab. So the Materials
  panel, the face selection filters, "Apply to Selected Faces" and the UV
  controls all worked on the preview and stopped at the bake: a mapper textured a
  level, pressed Bake, and got one material over everything with nothing said
  about it. The only log line on that path fired the other way round - when the
  flag was *on* and a cut forced the CSG path - so the silent case was the
  default one. The setting now defaults on, and the automatic fallback to CSG for
  a level with structural subtractors is unchanged, since independent face
  triangulation has no boolean subtraction stage and that fallback is what keeps
  the cuts. Turning it off is still a choice, and a bake that drops face
  materials because of it now says so.
- **The operation timeline's Replay button can be clicked, and its glyphs name
  the operation** (#437, #438). The button lives in the panel header, outside
  the entry it applies to, and was shown on hover and hidden again on
  mouse_exited - so any pointer path from the entry to the button hid it on the
  way, and `_hovered_index` went back to -1 so a press would have emitted
  nothing anyway. `replay_requested` never fired, which made
  `HFPluginUndoEvents.on_replay_requested()` - the only way to jump to a point
  in the timeline - unreachable from the UI. A click now sets a selection that
  only another click, a clear or the panel closing takes away, and the hover
  drives the detail line alone. The glyph and colour tables also tested the
  generic draw/brush/create case above most of the specific ones, and most of
  the plugin's undo action names contain the word "brush", so "Clear Brushes"
  was drawn as a creation in the create blue, and "Apply Brush Material" and
  "Assign Face Material" got different glyphs for the same kind of operation.
  The generic test is last now, destruction is first, and "bevel" and "prefab"
  have their own glyphs rather than falling through to the catch-all.
  `HFHistoryBrowser` calls the same two functions, so both surfaces are right.
- **The playtest starts the player standing on the spawn point** (#468). Two
  pieces of code held a model of the same player and disagreed about what a spawn
  marker is. `HFSpawnSystem` treats it as the feet - it builds its test capsule
  at `pos + PLAYER_HEIGHT / 2` and places a marker at
  `floor + FEET_OFFSET + height_offset`, which the user guide describes as extra
  height above the floor for safety, so the offset is already in the marker's
  position. `_resolve_playtest_spawn()` added `height_offset` a second time and
  handed the result to a `CharacterBody3D` whose capsule is centred on the node.
  With `height_offset` 0 the validator passed a spawn that started the body 0.7
  units inside the floor it was meant to stand on, and what happened next was
  left to `move_and_slide()`. The body is now derived from the marker in one
  place, half a player above the feet, and a test asserts the two scripts still
  agree about how tall a player is - which until now was a comment in one of them
  asking the other to match.
- **Crouch shrinks the player** (#469). The playtest HUD lists `Ctrl crouch` and
  what Ctrl did was pick a slower speed: `is_crouching` was assigned and never
  read again, `_ensure_collider()` built one 1.6-tall capsule at `_ready()` and
  nothing touched it afterwards, and the camera stayed at eye height. A mapper
  building a crawl space and pressing Ctrl to test it walked into the wall
  slowly, with nothing on screen to say whether the gap was too low or the crouch
  did not work - which is the specific thing playtesting is meant to answer. The
  capsule now shrinks, the body moves by half the change so the feet stay where
  they were, the camera comes down with it, and standing up tests that the taller
  capsule fits before it happens. A player who cannot stand up stays crouched,
  and the movement speed reads that state rather than the key.
- **The quick property popup and the control behind it now agree** (#447,
  #448). The double-tap popup (G G, B B, R R) restated the range of each field
  instead of taking it from the dock control it writes into, and none of the
  three pairs matched. The radius pair was the worst: the popup's own default
  was ten times the maximum of the control it wrote to, so opening R R and
  pressing Enter without typing anything set the surface paint radius to its
  limit. The brush size spin had `min` 0.1 with `step` 0.5, so the only values
  it could hold were 0.1, 0.6, 1.1 ... - it could not express a whole number at
  all, and opening B B on a 4 unit brush silently showed 4.1. `show_property()`
  now takes the min, max and step of the controls it stands in for.
  A committed brush size also went to two places, `input_state.drag_size_default`
  unclamped and the dock spins clamped, so the dock said 256 while the next
  brush drawn was 500.5 across; the controls are written first and the size is
  read back out of them, so there is one answer.
- **Set Cordon from Selection leaves a cordon that contains the selection**
  (#467). The button put the right AABB on the level and then copied the six
  numbers into the cordon spins, which were built with a range of +/-9999. Each
  assignment clamps to that range *and* fires `value_changed`, and
  `on_cordon_value_changed()` reads the six clamped spins straight back onto
  `cordon_aabb` - so a room at x = 12000 collapsed the cordon to a zero-width
  slab at the limit, the button left the cordon switched on, and the next bake
  produced an empty level with the control reading 9999 as though that were the
  number the mapper chose. The write-back is guarded with `syncing_grid` now, the
  way `_sync_grid_settings_from_root()` already guards the same six, and the
  range covers the coordinates a level actually holds: one structure builder
  piece can be 4096 across on its own, and Quake-family maps run well past that
  per axis. A cordon that still will not fit says so rather than being clamped in
  silence.
- **A tool setting is now held to its own schema, wherever the value comes
  from** (#450). `HFEditorTool.set_setting()` wrote whatever it was handed. The
  schema's `min`/`max` was read in exactly two places - `get_setting()` for the
  default, and the SpinBox `dock._build_tool_settings()` generates - so the
  constraint lived in one control and the tool itself had no opinion. A path
  drawn at width -16 built an inside-out corridor: a negative half-extent swaps
  the two sides of every corner ring and reverses the winding of all six quads,
  and `HFBrushSystem._usable_size()` - the one guard that knows a negative size
  builds a brush inside out - only ever saw the size, which it quietly
  corrected, and never the face array a CUSTOM brush actually renders and
  bakes. Three values outside one schema gave three different outcomes; they
  now all give the schema's. A value that is not a number is refused and the
  previous one kept. `_build_segment_brush()` also refuses a non-positive width
  or height outright rather than building a ring from it.
- **Every face of a new brush can show a texture** (#463).
  `FaceData.uv_projection` defaulted to `PLANAR_Z`, which maps `(x, y)` to
  `(u, v)`: on a face whose plane contains the Z axis, or one lying flat in Y,
  one UV axis is constant across the whole face and every point on it samples the
  same row of texels. That was four of a box's six faces, three of a wedge's five
  and one of a pyramid's, on the baked mesh as well as the preview, with the
  dock's "Apply + Re-project (Box UV)" there to correct the default by hand a
  face at a time. A new face uses `BOX_UV`, which resolves to its own dominant
  normal axis. Texture lock reads the same field and was the second casualty -
  `adjust_uvs_for_rotation()` declines any face whose projection plane the turn
  takes away, which under `PLANAR_Z` was every face of a default box under a yaw,
  so a rotate with texture lock on changed nothing at all.
  `_transfer_face_data()` carries the projection across a rebuild, so a saved
  level keeps whatever it was saved with.
- **A cylinder cap can show a texture too** (#463). The caps were not falling
  back to the projection as the rest did: `_face_from_ids()` carries the source
  mesh's UVs across when every vertex has one, and `CylinderMesh` maps both caps
  onto a *line* - every vertex of the top cap at `v = 0` and every vertex of the
  bottom at `v = 0.5`. Source UVs that span no area are refused now, because the
  projection is a far better map than one that cannot be seen.
- **A cylinder or a cone is built from the sides it was given** (#482).
  `radial_segments` was never set, so both stayed at Godot's default of 64
  whatever `sides` said - and `sides` is part of a brush: the `.hflevel` carries
  it, a preset stores it and `HFDuplicator.shape_signature()` counts it, so two
  brushes that differed only in `sides` were identical geometry with different
  signatures. The preview also disagreed with the bake, which builds its CSG
  through `PrefabFactory` and has always used 16. Below `MIN_ROUND_SIDES` the
  number is not honoured and the default is used instead: `sides` is 4 on every
  brush the Build tab makes and on every cylinder in a level saved before this,
  and the editor has PRISM_TRI and PRISM_PENT for the low counts, so a round
  shape is not how you ask for one. A greybox cylinder is 18 faces after the
  coplanar merge now rather than 66.
- **Entity properties are written into a `.map` in the notation a `.map` uses**
  (#479). A `.map` exists to be read by something else, and the Objects tab
  stores typed values: the colour picker writes a `Color` and the vector row
  writes a `Vector3`. `_entity_to_map_lines()` called `str()` on each one before
  the adapter saw it, so a colour reached the file as
  `"color" "(0.2, 0.4, 0.8, 1.0)"` - and the parentheses and the commas make the
  key unusable to a Quake-family compiler rather than merely differently scaled.
  The value keeps its type as far as the adapter now, which writes a colour as
  three numbers with no alpha, a vector as space-separated components, a flag as
  `1` or `0` and a float with the snapping the rest of the file uses. A hex
  string goes the same way, because `entities.json` gives a colour property a hex
  default and a colour the mapper never opened was reaching the file as
  `#ffffff`. The colour scale is one overridable method, since it is a per-format
  convention. The `.map` writer's no-adapter fallback used to `str()` everything,
  which is the notation this path exists to keep out of the file; it builds a
  base adapter instead.
- **The region memory budget now counts what it actually freed** (#446).
  `_unload_region()` is careful: it refuses to throw a region's chunks away if
  they could not be written to disk first, and says so. `_evict_for_budget()`
  subtracted the region's bytes from its running total whether or not the
  region went, so after one refusal it decided the budget had been met and
  broke out having freed nothing. On a level that has never been saved there is
  no region path at all, so every write fails and the Memory Budget spin in the
  Floor Paint tab did nothing whatsoever, in silence. The loop now skips a
  region it could not free, and when it runs out of candidates with the budget
  still over it says so once, naming the figures and - on an unsaved level -
  that the level needs saving before streaming can reclaim anything.
- **The selection filters reach every face, only the visible ones, and say when
  they match nothing** (#434, #435, #436). Walls was `|n.y| < 0.3`, Floors was
  `n.y > 0.7` and Ceilings was `n.y < -0.7`, so a face 17 to 45 degrees off
  level - a ramp, a chamfer, a bevelled edge, most of what a mapper opens a
  bulk face filter for - belonged to no button at all. The three now partition
  the sphere between them at one threshold. `_get_all_brushes()` also walked
  `_iter_pick_nodes()` with no visibility test, so every bulk filter selected
  faces on brushes hidden by a visgroup and the paint or material assignment
  that followed edited geometry the mapper had hidden precisely so it would not
  be; hidden brushes are now left out. And a filter that matched nothing closed
  in silence with the previous selection standing, in three different ways:
  they now all close and report what was looked for.
- **Loading an example level asks first and can be undone** (#443, #444). The
  Load button on an Example Level card called `clear_brushes()` and
  `clear_entities()` straight out, outside undo and with nothing asking - while
  the Clear Brushes button two sections up the same tab went through
  `_commit_state_action()`. An hour of work went with one click on a browsable
  list of tempting cards, and Ctrl+Z did nothing. The load now names what it
  will replace ("Replace 6 brushes and 1 entity with 'Simple Room'?") when the
  level is not empty, and the whole thing is one undo step. Rebuilding the card
  list also left the old cards in the container until the end of the frame,
  because `queue_free()` alone does not remove them, so the new cards were
  appended below them and the search - which indexed the examples by child
  order - filtered the dying half and never reached the live one. The cards are
  removed before they are freed, and the search reads each card's own id.
- **A paint layer is now the one the mapper chose, on the level's own grid**
  (#432, #433, #442). `remove_layer()` kept the active index by clamping it,
  which is only right when the removed layer is after the active one: deleting
  a layer below it shifted every later layer down and the paint target moved to
  a layer above the selected one, with nothing announcing it. `create_layer()`
  never checked the id was free, so two layers could share one `layer_id` -
  which is identity, not a label - and Godot renamed the colliding node to
  `@Node@9`; a repeated id is now uniquified to `roof_2` and the reason logged.
  And every layer holds its own copy of the grid while
  `_sync_paint_grid_from_root()` only wrote the template, so moving the level
  root left every painted floor, connector and scatter on the old world origin
  and a layer created afterwards landed on a different grid from the ones beside
  it. The sync now pushes origin, basis and cell size into every layer grid,
  keeping each layer's own `layer_y`.
- **A committed scatter is now owned, undoable and capped** (#429, #430, #431).
  Three things went wrong on the way from a scatter stroke to a scene. Align to
  Normal crossed the height field tangents the wrong way round, so the "normal"
  was `(0, -1, 0)` on flat ground and every instance was placed upside down.
  Nothing refused a large stroke: the candidate count is quadratic in the
  radius, so radius 1000 at density 1.0 laid out three million transforms and
  took the editor with it - scatter now refuses past 50,000 the way
  `HFDuplicator` refuses past 256 copies, naming the count and pointing at the
  radius and density. And the committed `MultiMeshInstance3D` had no owner, so
  it was never written into the `.tscn` and a mapper lost every instance on the
  next save and reopen; the commit now runs inside one undo action and gives
  the node the same owner the level's other generated nodes have.
  `HFFoliagePopulator` gets the owner too.
- **Saving a level no longer rounds every heightmap sample to 8 bits** (#445). A
  paint layer's heightmap is a `FORMAT_RF` image - one 32 bit float per sample -
  and `HFHeightmapIO` stored it as a base64 PNG. PNG has no float channel, so
  Godot wrote it as 8 bit and the decode converted the 8 bit result back to RF:
  256 height values survived across the whole range, anything above 1.0 or below
  0.0 was clamped to the limit, and each save re-rounded the already rounded
  data. `HFStateSystem.capture_state()` uses the same encoder, so an undo of an
  unrelated operation moved the terrain. The heightmap is now stored as the raw
  float buffer, zstd compressed, behind a small header, which loses nothing. A
  base64 PNG written by an older version is still recognised and loaded.
- **A shortcut rebound onto a chord another action already uses was accepted in
  silence** (#410). Nothing compared a new binding against the others, so
  `matches()` answered true for both, and `plugin_input_router` tests actions one
  at a time and returns on the first hit - so the earlier check won and the other
  action became unreachable with no message anywhere. Rebinding Hollow to Ctrl+G
  got you Group, forever, with no way to find out why. A plain "this chord is
  taken" check would be wrong, because the defaults share six chords on purpose:
  `E` is Extrude, Erase and Edge Mode, `R` is Rotate and Ramp, and `X`, `Y` and
  `Z` are axis locks and paint mirrors. The router gates each family on its mode,
  so none of those pairs can both fire. The check is mode-aware to match: two
  actions clash only when they share a chord and can fire at the same time.
  `set_binding()` reports one, loading a hand-edited keymap reports each pair
  once naming the file, and the shortcut dialog marks the binding in amber with a
  tooltip saying what else uses it - which is before the fact rather than after.
- **Toggling the measure tool's align off forgot which ruler was the reference**
  (#405, #411). `_toggle_align()` called `_remove_snap_reference()`, which sets
  `_snap_ref_index` to -1, so the branch below it that reuses the chosen ruler
  could never run: pressing A again fell through to the last branch and silently
  took the newest ruler instead. Nothing said the reference had changed; the snap
  line just moved, and everything snapping to it went somewhere else. Align off
  now clears the snap line and keeps the choice, which is what the HUD line and
  that unreachable branch both say was intended; leaving the tool still forgets
  it. The snap system itself also accepted a line with no direction:
  `Vector3.ZERO.normalized()` is `Vector3.ZERO`, so every point inside the
  threshold projected onto the line's origin. A ruler with both ends on one point
  draws exactly that, and the rule lived in the one caller that checked rather
  than in the system that depends on it. `set_custom_snap_line()` refuses a
  direction that is not one, keeping any line already set, and `snap_threshold`
  refuses a value of zero or less rather than turning every geometry candidate
  off in silence.
- **A palette of materials that could not be found was reported as success, and
  as an empty palette** (#414, #415). `load_library()` keeps a slot and drops the
  material when a path no longer resolves, which is right - `FaceData`
  `material_idx` indexes that array and compacting it would repaint the level -
  but it said nothing about it and returned `true`. Loading a library of three
  paths that had moved gave a palette of three nulls, no warning, no count and
  no list. Each missing path is now named on load with a count after it, and
  `get_missing_library_paths()` and `get_missing_count()` report the same thing
  to a caller. The status board counted only the slots that resolved, so a
  palette of unresolved entries was indistinguishable from no palette at all and
  the board said "Material palette / Empty / Everything bakes with the default
  grey. Fine for greyboxing." It is not fine: those slots are the ones every face
  indexes, and `validation_system.validate()` on the same level reports an issue
  for each of them. The board carries both numbers now - "3 slots, 0 loaded" at
  PROBLEM with the load action offered, and "4 of 6 loaded" at WARN when some
  came back.
- **Painting a face threw away everything about its material but three scalars,
  and replaced a ShaderMaterial outright** (#412, #413). The editor preview and
  the bake both built the painted material as a bare `StandardMaterial3D`
  carrying copies of `roughness`, `metallic` and `albedo_color`. So a painted
  face lost its normal map, its roughness and metallic maps, its emission and
  its UV transform. On a tiled wall the UV scale going back to 1 is the visible
  one - the texture on the painted face is suddenly four times the size of the
  one beside it - and the normal map vanishing is the one people spend an
  afternoon on before finding it. The composite only ever needed to replace the
  albedo, so it now duplicates the base and sets `albedo_texture` on the copy,
  which keeps everything else including slots added to `StandardMaterial3D` in a
  future Godot version. A `ShaderMaterial` failed the `is StandardMaterial3D`
  test, so the new material was built with nothing on it but the composited
  albedo and the shader was silently gone from that surface. It is now refused
  rather than substituted, the way `HFMaterialAtlas.build_atlas()` already puts
  one in `fallback_keys` rather than pretending it can pack it: the face keeps
  its shader, the paint is not drawn, and a warning says so once. Both call
  sites now share one composite on `FaceData` rather than keeping a copy each.
- **A level with more texture than the atlas holds took the atlas down** (#416).
  `_shelf_pack()` reports failure by returning zeros, and `build_atlas()` read
  `width`, `height` and `placements` without looking at `success`. So the
  failure became an `Image.create(0, 0)` error and then an out-of-bounds on the
  first placement lookup, the function unwound, and the caller got `null` where
  it expected an `AtlasResult` - no fallback, no partial pack, no message.
  Twenty 2K textures does it: each one is a legal tile, and together they are 84
  million pixels against the 16 million a 4096 atlas holds, which is an ordinary
  art budget rather than an edge case. The packer now fills the biggest atlas it
  can and names what would not fit, and those materials go into `fallback_keys`
  with the reason in a new `AtlasResult.overflow_keys`, the way
  `skipped_channels` carries a reason for a PBR slot. The bake already renders
  fallback keys on their own surfaces, so the level bakes with every material on
  it and a warning saying how many did not make the atlas.
- **User preferences trusted the file completely and were not written
  atomically** (#408, #409). `load_prefs()` assigned the parsed JSON straight to
  `data`, and every accessor then reads its container into a typed local, so one
  value of the wrong type was not a wrong preference - it was an error on every
  call that touched it. A `collapsed_sections` of `"all"` broke every section
  read, `add_recent_file()` aborted before its write so the path was dropped
  without a word, and `dismiss_hint()` could not record a dismissal so the hint
  came back forever. The loaded file is now held to a schema: a value that
  cannot be used is replaced by the default and reported once naming the file
  and the key, the way `HFKeymap._validated()` does for the keymap, and a key
  this version does not know is kept rather than thrown away. A number outside
  its usable range is clamped, on load and in `set_pref()`, so an autosave
  interval of -1 or a grid snap of 0 cannot reach the disk. `save()` also opened
  the destination with `FileAccess.WRITE`, which truncates first, so an editor
  that went down mid-write left a file that would not parse - and a file that
  would not parse was silently replaced by the defaults and overwritten by the
  next save, taking the evidence with it. The write goes beside the file and is
  moved into place, and a file that cannot be read is kept as
  `hammerforge_prefs.json.unreadable` with a warning that says why.
- **An entity I/O input named after a Node method called it, and one malformed
  entity took its whole subtree out of the wiring** (#406, #407).
  `_deliver_to_target()` resolved an input name by calling a method of that name,
  and `has_method()` answers for everything `Object` and `Node` implement. The
  snake_case fallback made the collision easy to hit from ordinary PascalCase
  naming: an input called `QueueFree` deleted the target, `Free` would have
  deleted it mid-frame, and `Hide`, `SetScript` and `ReplaceBy` are each one typo
  away. The input name is free text from a dock field with nothing between it
  and there, so a name that collided with the engine was destructive while a
  plain typo was silent. Only methods the target's own script defines are called
  now; an engine method, or a name starting with an underscore, falls through to
  `_on_io_input` and the user signal with a warning naming both. Separately,
  `_collect_connections()` read `entity_io_outputs` into a typed local, so one
  entity whose metadata was not an Array - a hand-edited scene, an older format -
  was a runtime error that unwound the function including the recursion at the
  bottom of it, and everything nested under that entity dropped out of the
  wiring. This is the shipped game, not the editor: the level loads, the error
  goes to a log nobody reads, and a door somewhere never opens. The value is
  type-checked, the bad entity is skipped with a warning naming it, and its
  children are scanned as usual.
- **A decal was not part of the level** (#403, #404). `_place_decal()` added a
  `Decal` node under the `LevelRoot` and nothing else knew about it.
  `capture_state()` had no decal key, and a `.hflevel` is what `capture_state()`
  returns, so a decal was gone after a save and reload - of the format the
  editor treats as authoritative and the one autosave writes. Placing one also
  registered no undo action, so Ctrl+Z undid whatever the user did before the
  decal and left the decal in place, with no delete gesture to remove it. Decals
  now live under a `Decals` container on the `LevelRoot`, are captured and
  restored with the rest of the level state, and a placement is wrapped in the
  same state capture and restore pair the polygon and path tools use. Each decal
  also gets a name of its own: they were all called `HFDecal`, so the second one
  in a level came back as `@Decal@15`. The ghost under the cursor stays out of
  the container and out of the level, as before.
- **The extrude tool's ghost was a brush in the level, in the wrong place, and
  its ids were not unique** (#400, #401, #402). The preview was a real
  `DraftBrush` parented into `draft_brushes_node`, the container
  `_iter_managed_brush_nodes()`, `_iter_pick_nodes()`, `capture_state()` and the
  save all walk, so mid-drag the level had a brush in it that nobody made: an
  undo snapshot or an autosave taken during the drag stored the ghost, and the
  snap system offered its corners as targets. It now goes into a container of
  its own the way every other preview in the editor does. It was also positioned
  before it was added to the tree, and `global_position` is tree-relative, so the
  engine returned an identity transform twice per preview update and the ghost
  sat at the origin rather than on the face under the cursor - on a brush turned
  45 degrees the green volume had nothing to do with what committing would
  build. The transform is written after `add_child()` now. And the tool minted
  its own brush ids from the direction and the millisecond clock, so two
  extrusions committed in the same millisecond claimed the same id, ids collided
  across sessions whenever the tick counts lined up, and `id_counter` never
  advanced. Ids come from the brush system, like every other created brush's.
- **The polygon tool built brushes out of degenerate input** (#398, #399). The
  convexity gate skips any cross product under 0.001 before it looks at the
  sign, so for points all on one line it never disagreed with itself and
  reported a convex polygon. Three collinear clicks and Enter gave a five-faced
  brush with an extent of zero that validated clean, saved, baked and sat in
  front of every pick. The same blind spot let a vertex be placed on top of one
  already there, which built side quads spanning no area that still took a
  fallback normal, a UV projection, a snap target and a place in the bake. A
  click within a hundredth of a unit of a vertex already placed is now rejected,
  and a polygon that encloses no area is refused at the point it would extrude,
  with a warning saying so. The convexity gate itself is unchanged: a run of
  collinear points part-way through a polygon is a real shape, and it is the
  finished polygon's area that decides.
- **Every path tool brush was wound inside out** (#397). `_build_segment_brush()`
  and `_build_miter_brush()` wrote their rings the opposite way round from the
  clockwise-from-outside order every other brush in the editor uses, and nothing
  negated the normals afterwards. A straight corridor came out with all six faces
  pointing at its own centre, and baked with a signed volume the opposite sign
  from the same box drawn with the draw tool: invisible from the inside and
  exported with inverted planes. The stairs, railing and trim extras all go
  through the segment builder, so they carried it too. Face winding data moves to
  version 3, and a brush loaded at an older version whose every face points at
  its own centroid is migrated on load. That signature is what an inverted convex
  solid looks like and a correctly wound solid cannot, so levels already saved
  with path corridors come back the right way out and brushes that were always
  right are not touched.
- **A vertex move that bowed a face out of plane passed the convexity check**
  (#364). `validate_convexity()` tested one thing: that no vertex sits in front
  of any face plane. It never tested whether a face is still a plane. Every face
  of a box is a quad, and moving one of its four corners bends it while the
  other three stay behind the plane through the first three, so the check passed
  and the move committed. Pulling one corner of a 64 unit box 256 units left the
  worst face sitting 62 units off its own plane. Everything downstream reads a
  face as a plane: the `.map` export writes it as three points, clip and carve
  intersect it, and the bake triangulates it while collision and lighting use
  the plane, so the exported solid stopped being the one on screen. Each face is
  now measured against the plane through its own first corner, with a tolerance
  that scales with the face, and a move that bends one is refused and reverted
  the same way a non-convex one is. The refusal now says which of the two it
  was. A move that keeps every face flat, such as sliding a whole side along its
  own normal, still commits.
- **Changing a bake setting did not invalidate the bake** (#376). `bake_dirty()`
  rebuilt only what brush dirty state said needed rebuilding, and the settings
  were not part of what could be dirty — so the realistic sequence did the wrong
  thing quietly: hide a visgroup to work on something, bake to check it, turn
  "bake visible only" off, bake again, and the level that ships is missing every
  brush in that visgroup. The second bake finished, said it succeeded, and left
  the previous result standing. `bake_visible_only` is only the easiest to
  measure; every setting that decides what goes into the bake or how it is built
  had the same problem, several of them less visible in the result than a missing
  box. The bake system hashes those settings and compares against the ones the
  last successful bake ran with, so a setting change is a change. A hash rather
  than a flag per setter, because most of these properties had no setter and the
  hash covers the `.hflevel` load path for free.
- **`merge_brushes_by_ids()` enforced neither rule `can_merge_brushes()` refuses
  on** (#383). The operation collected whatever ids it could find and took the
  first brush's operation for the result, so merging an additive brush with a
  subtractive one succeeded — a subtractive brush is a hole, and merged into a
  solid the mapper's doorway became a wall under a message saying "Merged 2
  brushes" — and a selection with one stale id merged the subset and reported the
  count it merged. The reachable path is a redo: the pre-check runs before the
  undo action is opened, and the undo entry stores the method and the ids, so a
  redo calls the operation directly against a level that has moved on.
  `merge_brushes_by_ids()` calls the check, which is side effect free and already
  returns the right message for each case.
- **The bake and grid settings that take a number were unbounded** (#373). #361
  did this for the terrain settings; these are the same list and were not
  touched. 22 of 23 out-of-range values landed and stayed. The dock SpinBoxes
  have ranges so the editor UI cannot produce them, but the `.hflevel` can: it is
  JSON, it is hand-editable, it gets merged, and it gets written by older builds
  with different defaults — and an `@export_range` constrains the inspector
  widget only, not an assignment or a load. Each of these now has a clamping
  setter with a finiteness guard first, since `clampf()` and `maxf()` both pass
  NaN through, which is exactly how `grid_snap`'s `max(value, 0.0)` let one past.
  That one mattered most: every consumer is written
  `grid_snap if grid_snap > 0.0 else <fallback>`, so a NaN read as "snapping is
  off" everywhere while the dock still showed a number.
  `apply_hflevel_settings()` writes the properties, so the load path goes through
  the setters and is covered by the same change.
- **A cordon AABB with a negative size baked an empty level and reported
  success** (#377). An AABB with a negative size is a constructible value of the
  type and is not a region: Godot's `intersects()` errors on it and returns false
  for everything, so every brush read as outside the cordon. Nothing said so —
  the bake reported success and the cordon wireframe draws the same box either
  way — and the dock's six min/max SpinBoxes are the natural way to produce one.
  `cordon_aabb` has a setter that refuses a non-finite position or size and calls
  `.abs()` on a negative one, which is the fix Godot's own error message names
  and makes a min/max pair entered in either order mean the same region.
- **`validate_level()` could not see a brush whose size was NaN** (#371). Its one
  size check was a comparison, and every comparison against NaN is false — an
  infinite size is legitimately `> 0.0` as well. The validator is the backstop:
  a mapper with a NaN-sized brush saw a clean badge, baked, and got a mesh with a
  poisoned AABB with nothing anywhere naming the brush responsible, and no way to
  find it by eye because a NaN size draws nothing. Finite is tested first, so the
  report says what is actually wrong, and `auto_fix` puts the default size back.
  The brush transform is checked the same way, and reported rather than repaired,
  because there is no honest repair for a non-finite origin.
- **`validate_level()` checked no brush geometry, and owned two repairs nothing
  called** (#372). `weld_brush_vertices()` and `fix_non_planar_faces()` worked and
  were tested and had no caller outside the suite — no dock button, no menu item,
  and not `validate()` itself in `auto_fix` or out of it. Meanwhile a brush with
  no faces, a face bowed off its own plane, and a face with a NaN vertex all
  validated clean. Fixing the setters that create those states does nothing for a
  `.hflevel` saved last week or a `.map` imported from another editor, which is
  the ground the validator covers. `validate()` now reports all four, and
  `auto_fix` deletes a brush with no faces (there is nothing to repair), calls
  `fix_non_planar_faces()` on a bowed one and `weld_brush_vertices()` on vertices
  a weld apart, and leaves a non-finite vertex reported only.
- **A group could be named with nothing but whitespace** (#374). #349 fixed this
  for visgroups and left a comment saying exactly what was wrong with the guard;
  sixty lines further down in the same file `create_group()` still tested
  `group_name == ""`. It matters more for a group than for a visgroup, because a
  group is the unit the editor moves and duplicates together: `"Arch"` and
  `"Arch "` were two groups, so half the brushes the mapper thought they had
  grouped moved without the other half, and the group list looked right because
  both rows read "Arch". Names are stripped and a name that strips to nothing is
  refused, in `create_group()` and in `group_selection()`, which writes the same
  string into node meta.
- **An `entities.json` with an "entities" key of the wrong type left the editor
  with no entity definitions** (#380). The loader falls back to the built-in
  classes when the file is missing, unopenable or unparseable — but it read the
  entries into a typed local, so a file that parsed with `"entities": "nope"` was
  a runtime error, and GDScript unwound the function past every fallback below
  it. `load_entity_definitions()` clears the table before it reloads, so the
  level was left with an empty definition table: no class could be placed and
  every entity already in the level lost its property schema and its colour. A
  valid JSON file with one key of the wrong type is the most likely hand-edit
  mistake, not the least. The value is read before it is assigned, in all three
  readers.
- **An entity class could be defined with a whitespace-only classname** (#381).
  The classname is the identity of the class in three places at once: the key in
  `entity_definitions`, the row in the class dropdown, and the `"classname"`
  field written into the exported `.map`, which is what the target engine reads
  to decide what the entity is. A blank one was a blank dropdown row that could
  not be told from another and a malformed entity in the export, and it survived
  every round trip. Classnames are stripped before the emptiness test and stored
  stripped, so `"door"` and `"door "` are one class and the project overlay and
  the plugin base agree about which. A file that defines the same classname twice
  now warns instead of the second one silently winning.
- **A placed prefab brush kept visgroup names the receiving level had never
  registered** (#368). `capture_from_selection()` strips `brush_id` and
  `group_id` because they only mean something in the level the selection came
  from; `visgroups` is the same kind of thing and was kept. A prefab library
  shared between levels is the normal way to use prefabs, so the placed brush
  routinely ended up in a group with no row in the visgroup panel — it could not
  be shown, hidden, renamed or deleted, `refresh_visibility()` skipped it, the
  partitioned bake still read the membership off the node, and the `.hflevel`
  kept it. Stripped on capture now, for entities as well as brushes.
- **A prefab restore could reissue a live instance id** (#369). `restore_state()`
  took `next_instance_id` from the saved data and never reconciled it against the
  records it had just restored, so a state whose instances list held `pfx_1` with
  a counter of 1 — exactly what a `.hflevel` saved before the counter was
  captured produces — issued `pfx_1` again for the next placement. The registry
  write is a plain dictionary assignment, so the second registration overwrote
  the first silently and the first placement's nodes were left tagged with an id
  that now resolved to a different prefab. The counter is derived from the
  restored records, for entity uids as well, and `register_instance()` warns
  rather than overwrite.
- **A malformed `.hfprefab` left the level's signal batch open for the session**
  (#370). `from_dict()` checked that `brush_infos` was an Array and not what was
  in it, so an entry that was not a Dictionary reached `info.duplicate(true)` in
  `instantiate()`. GDScript has no exception handling, the function unwound past
  its own `end_signal_batch()`, and from then on `_emit_or_batch()` queued every
  level signal and emitted none: the brush list, the entity list, the visgroup
  panel and the validation badge all froze while editing carried on working, with
  nothing pointing back at a prefab that failed to place. Non-Dictionary entries
  are dropped on load with a warning, and `LevelRoot` releases a signal batch
  that has been open for more than a second with a warning, so no skipped
  `end_signal_batch()` can take the dock down again.
- **A non-finite vertex move was accepted and wrote NaN into the face data**
  (#365). `validate_convexity()` is written as a lower bound (`d > 0.02`) and
  every comparison against NaN is false, so a NaN vertex read as behind every
  plane of the brush and the move committed. A vertex position is the geometry
  rather than a parameter used to build it, so the result poisoned the AABB and
  the normal, propagated through clip and carve into brushes that were never
  touched, and survived the save with no editor action that put it back.
  `move_vertices()` and `update_drag_absolute()` refuse a non-finite delta before
  any face is touched.
- **Merging every vertex of a brush left a live brush with no faces** (#366).
  Every face collapsed to a point and was removed, and `validate_convexity()` was
  then asked about a brush with no faces — its `faces.size() < 4` early-out
  returns true, so the merge was accepted. The brush stayed in the draft
  container, selectable, counted and saved, drawing nothing and with no vertex
  left to move it back. A merge that would leave fewer than four faces is refused
  with a message, and the snapshot is restored.
- **Splitting an edge could tell a wall it was a floor** (#367). `split_edge()`
  inserts the midpoint *on* the edge, so when the split edge is the one at index
  0 the face's first three vertices are collinear by construction. The normal was
  computed from exactly those three, measured zero, and fell back to
  `Vector3.UP` — and the normal is what the convexity check, the bake and the
  `.map` export read, not the vertices. `_compute_normal()` uses Newell's method
  over the whole polygon now, which is correct for any planar polygon regardless
  of collinear runs, and `split_edge()` rotates the vertex list so it starts at
  an actual corner. The convexity check builds its own plane from the first three
  non-collinear vertices rather than reading the face normal, because an
  area-weighted average is the one plane that hides a bend.
- **The resize path took sizes the create path refuses** (#378). A brush gets
  its size two ways and the two disagreed completely. `create_brush_from_info()`
  puts a size through `_usable_size()`, which floors a zero extent, makes a
  negative one positive, warns about both, and refuses a non-finite one outright.
  `set_brush_transform_by_id()` — the dock's size fields, the gizmo commit and
  every scripted resize — wrote the value straight onto the property. A negative
  size built the brush inside out, a zero size built no volume, and a NaN size
  poisoned the AABB with no editor action that put it back. The resize path goes
  through the same funnel now, and refuses a non-finite position with it.
- **A non-finite nudge offset sent the selection to nowhere** (#379). The only
  guard was `offset.is_zero_approx()`, which is a magnitude test that a NaN
  passes. The offset comes from the dock's transform fields and from the
  arrow-key nudge, which uses `grid_snap`, so one bad number moved every selected
  brush to a position with no AABB, nothing drawn to click, and the `.hflevel`
  keeping it. `nudge_brushes_by_id()` and `nudge_entities_by_paths()` refuse a
  non-finite offset.
- **An array with a non-finite layout number built every copy at a NaN position**
  (#382). `can_generate()` checked the copy count and the source count and never
  looked at the numbers that decide where a copy lands, so five copies meant five
  lost brushes rather than one. `linear_placements()`, `radial_placements()` and
  `grid_placements()` lay out nothing when the offset, spacing, step, rise or
  pivot they were handed is not a number, and `can_generate()` takes the layout
  parameters so the refusal says which fields to check.
- **A grid array with a negative axis count was built rather than refused**
  (#346). The linear and radial paths refuse a count below one with a message and
  a fix hint; the grid path clamped `(-2, 2, 2)` up to `(1, 2, 2)` first, so
  `can_generate()` was asked about three copies and an array the mapper never
  described was created without a word. `grid_copy_count()` answers -1 for a
  count below one on any axis, which the existing refusal already covers, and
  `generate_grid()` no longer clamps — so the record holds the counts that were
  asked for rather than ones nobody typed.
- **A visgroup could be named with nothing but whitespace** (#349). The guard
  tested `vg_name == ""`, so `""` was refused and `"   "` was not: the visgroup
  existed, showed in the dock as a blank row, could not be told apart from
  another blank one, and was saved into the `.hflevel` on its members. Names are
  stripped and a name that strips to nothing is refused, on create and on rename.
  Stored stripped as well, so `lights` and `lights ` are one visgroup rather than
  two a keystroke apart.
- **Surface paint layers stacked on a face without a cap** (#351). 64 layers on
  one face is 64 walked on every `rebuild_preview()`, written into the
  `.hflevel` and read back, and past a handful the composite is not visibly
  different — `get_painted_albedo()` blends them at every texel, so each extra
  one is preview time, save size and load time for nothing. A face takes at most
  8, refused with a message that says the limit, checked in the dock before the
  undo action opens so Add does not report success over a layer that was not
  added. `SurfacePaint` honours the same cap, because painting into a layer index
  creates the layers below it. `remove_surface_paint_layer()` returns whether it
  removed something, so a no-op can be told from a removal.
- **The heightmap scale and the terrain layer height took any number** (#350).
  #320 refused a non-finite value at the displacement paint setters for this
  reason; the terrain layer has the same two knobs and did not get the same
  treatment. `height_scale` multiplies every height on the layer and `layer_y` is
  the plane its geometry is built on and the paint tool's raycast plane, so a NaN
  in either put the whole generated layer somewhere that is not a place — and it
  is saved with the layer, so reopening the level brought it back. Both refuse a
  non-finite value now. A heightmap scale of zero takes a floor rather than a
  refusal: it is not non-finite, but it multiplies the sculpt by nothing and
  reads to a mapper as the terrain having gone, and a very flat terrain is still
  a thing to want. The floor is on the magnitude, so a negative scale still turns
  the sculpt upside down.
- **Region streaming size and memory budget had no ceiling** (#352). Of the three
  settings, the streaming radius was clamped at both ends, the region size below
  only, and the budget not at all. `region_size_cells` is the divisor that turns
  a cell index into a region coordinate, so a million-cell region is the whole
  world in one region: streaming reports as enabled, the radius-2 neighbourhood
  is 25 of those, and the budget cannot be met by evicting anything because there
  is nothing smaller than one region to evict. Both are clamped at both ends now,
  and `load_region_index()` goes through the setters, because a sidecar written
  by an older version or by hand is exactly the caller they are for.
- **A malformed `.hflevel` emptied the level instead of refusing to load**
  (#347). `restore_state()` cleared the level and then read the state it had been
  handed, so a key holding the wrong kind of thing gave a raw engine error with
  the level already gone. It is not an internal-only path: `load_hflevel()` lands
  there, so does undo, a prefab drop and a whole-level replace, and a `.hflevel`
  is JSON on disk that gets truncated, hand edited, written by an older version
  or synced half finished. `HFValidation.level_state_problem()` checks the shape
  before anything is cleared, and a state that does not pass leaves the level
  exactly as it was and says why. Only the keys `restore_state()` types are
  checked, and only when present, so a state from a newer version is not refused
  for carrying something extra.
  - **One unreadable entry costs that entry, not the load.** A brush or entity
    entry that is not a dictionary is skipped and counted, the way the `.map`
    importer already handles a malformed brush (#318), and the count is reported.
  - Restoring a state no longer writes `pending` and `committed` flags back into
    the caller's own dictionaries.
- **A brush with a size that is not a size was built rather than skipped**
  (#348). #289 and #311 made `create_brush_from_info()` coerce a zero or negative
  size, and `maxf()` passes a NaN straight through, so a state restore — the load
  path, and the undo replay — built a brush whose AABB then poisoned the level
  AABB, the chunking and the saved file, with no editor action able to fix it.
  A non-finite size is refused at that same entry point, so every caller gets it:
  there is a nearest size a user plainly meant by zero, and there is no nearest
  size to a NaN.
- **Duplicating a wired entity left two entities on one address** (#341). I/O is
  addressed by the authored name, and `build_duplicate_entity_info()` copied it
  along with everything else — so `find_entities_by_name("door_1")` returned both,
  every output aimed at `door_1` fired at both, and there was no way to aim at
  one of them. It survived a save and a `.map` export, where the ambiguity became
  the compiler's problem. The copy takes the next free name now: `door_1` becomes
  `door_2`, and a name with no number on the end gets one. Its own outputs are
  left alone on purpose — a copy of a button should go on firing at the door the
  original fired at. `validate_level()` reports two entities sharing an address,
  which a paste, an import or a hand edit can also produce.
- **Entity outputs accepted blank names and a NaN delay** (#342). All of them
  reached the exported `.map` as lines that read like wiring and do nothing, and
  this project's own importer drops three of six such lines on the way back in —
  so the dock showed connections the round trip had already lost.
  `add_entity_output()` refuses a blank output, target or input name and a delay
  that is not zero or more seconds. `validate_level()` reports a connection with
  a field missing, and the `.map` importer now counts the lines it drops and says
  so in the import result instead of dropping them in silence. A line only counts
  as a loss when it has the five fields of a connection and fails on one of them;
  an ordinary entity property is not wiring.
- **A face's material slot was never checked against the palette** (#343). Any
  integer could be assigned and was stored, saved and read back, so the bake, the
  `.map` exporter and the UV editor each fell back to something that is not the
  material the mapper picked — the face silently becomes `__default` in the
  export. The three `assign_material_*` paths refuse a slot that is not `-1` and
  not an index into the palette, and `validate_level()` now also reports a slot
  *below* the default rather than only one past the end, with the same reset.
- **`set_face_uv_params()` wrote a UV transform the mesh cannot use** (#344). A
  non-finite scale, offset or rotation reached the mesh's UV channel, where the
  vertex is discarded or drawn undefined depending on the driver, and it survived
  the save — with the geometry still looking right, which is why nobody thinks to
  look at the UVs. A scale component of zero collapsed the whole face onto one
  texel. Both are refused. A negative scale is still allowed: it mirrors the
  texture, which is a thing to want.
- **`reproject_face_uvs()` stored any integer as a UV projection** (#345). The
  projector falls through its `match` to the `(x, y)` branch, so the face got a
  projection nobody chose, no dock control can show, and the `.map` exporter
  wrote out whatever the fallback produced. The setter and
  `assign_material_and_reproject()` refuse one, `FaceData.from_dict()` falls back
  to `PLANAR_Z` so a file cannot smuggle one in, and `validate_level()` reports
  and resets one that is already there.
- **A bevel radius of zero built a bevel nobody asked for** (#330). `0` is how a
  user says "actually, no bevel", and `bevel_edge()` coerced it — and a negative
  radius — to 0.01, returned true, and left an inverted cap triangle. Both are
  refused now, the way `can_hollow_brush()` refuses a wall thickness of zero.
  - **The inverted cap was not a winding problem.** `FaceData._compute_normal()`
    called a face degenerate when the raw cross product of its first two edges
    came out under `0.0001`, and that quantity grows with the *square* of the
    face, so a 0.01-unit cap on a 64-unit brush measured `4e-5` and was handed
    `Vector3.UP` regardless of how it had been wound. Both caps of a small bevel
    came out facing the same way, one of them into the solid. The edges are
    normalised before the cross now, so what is measured is the angle between
    them and the answer does not depend on how big the face is. Three points in
    a line are still degenerate, which is the thing the check was for.
- **Inset accepted numbers it could not use** (#339, #340). `maxf()` does not
  clean a NaN and the height was never looked at, so both went into the vertex
  arithmetic and a brush came back with a non-finite extent while the call
  reported success. Both are now refused, along with an inset distance of zero
  or less — the same coercion #330 removes from the bevel.
  - **A recessed inset no longer turns its walls inside out.** The side faces
    were wound on the assumption that the inset boundary is in front of the
    original one. A negative height puts it behind, which inverted every wall.
    Which way a wall faces is now taken from the height: a raised inset is a
    boss and its walls face away from the middle of the face, a recess is a pit
    and its walls are seen from inside it, and at zero height the ring is flat
    and is part of the original surface.
- **A generator built a structure out of NaN brushes** (#336). Every builder
  checks its settings with comparisons like `radius <= 0.0`, and a NaN fails all
  of them, so it passed every check and the arithmetic ran on it. 27 field and
  value combinations across the four types produced structures where every piece
  had a non-finite position or extent, and `create_generator()` reported success
  over them. The dock's spinners cannot produce one, but a regenerate from a
  `.hflevel`, an undo replay and a script all can.
- **Generator dimensions and counts had no ceiling** (#337, #338). The schema's
  `max` was the dock's SpinBox and nothing else, so an arch could be asked for
  129,000 segments — 129,000 brushes in one call that reported success — and a
  stairs could be built 8,200,000 units tall, far past where a float32 position
  holds a 1-unit grid. `HFGeneratorSchema.check_ranges()` now holds every caller
  to the schema's own maximums, so the schema is one description of what a field
  may be rather than a description for the dock and nothing for anyone else, and
  a new builder gets the rule for free.
  - Both checks run in `HFGeneratorSystem.validate()`, before the builder sees
    the settings. A level saved with an out of range structure still loads — the
    pieces are saved as brushes and only re-linked — and a regenerate refuses
    before anything is deleted, so the structure stays as it was.
- **Texture lock tipped the texture on every wall of a rotated brush** (#333).
  The counter-rotation was applied to every face at the same angle whatever axis
  the brush turned about, so a yaw — the most common thing a mapper does — left
  four faces of a box a quarter turn out and the mapper fixing UVs by hand
  afterwards. It is now derived from the face's own projection: a turn that keeps
  the projection plane where it is folds into `uv_rotation`, with the sign taken
  from the projection rather than assumed (PLANAR_Z reads `(x, y)` and PLANAR_Y
  reads `(x, z)`, so the two go opposite ways round), and a half turn that puts
  the plane the other way up folds into the V scale. A turn that swings a face
  out from under its own projection cannot be written as a UV rotation at all, so
  that face is left alone and its texture travels with the brush upright, instead
  of being tipped.
- **A UV rotation was never wrapped, so a round trip was not a round trip**
  (#334). Four 90-degree turns left every face at `-2 pi` rather than `0`, so a
  level saved afterwards differed from the same level saved before, the exported
  `.map` said `-360` where it meant `0`, and a long session walked the angle off
  to where a float32 has no fraction left. `adjust_uvs_for_rotation()` and
  `set_face_uv_params()` both wrap into `[-pi, pi)` now.
- **Rotate and flip wrote a NaN transform onto a brush** (#335). Neither checked
  the angle or the pivot it was handed, so a non-finite value from an undo
  replay, a numeric field or a script went into the basis and the origin and
  stayed there — poisoning the brush AABB, the level AABB, the bake and the
  saved file, with no editor action able to recover it. Both refuse a non-finite
  argument and log, the way `can_hollow_brush()` already does. An axis index
  outside 0-2 is refused too rather than falling through to Z, which used to
  turn the selection about an axis the caller never asked for.
- **Five brush primitives were built inside out** (#313). `PRISM_TRI`,
  `PRISM_PENT`, `OCTAHEDRON`, `DODECAHEDRON` and `ICOSAHEDRON` came out of
  `create_brush_from_info()` with every face normal pointing at the brush
  centre, so `validate_convexity()` called a convex prism broken, the bake ran
  inside out, and `.map` export wrote a hull that is not a solid. The prism
  builder and the octahedron and icosahedron tables now wind clockwise from
  outside; the dodecahedron sorts its ring the other way round for the same
  reason. The editor preview is cull-disabled, which is why this looked fine in
  the viewport and only showed at bake or export.
  - **Levels saved before the fix are migrated on load.** Faces are serialized
    verbatim, so the inversion was in every `.hflevel` that holds one of those
    five shapes. `winding_version` is 2, and a v1 face on one of the five runs
    the centroid migration the v0 path already uses. It is exact there because
    all five are convex, and no other shape is touched, so a torus still loads
    as it was saved.
- **Every bevel left the brush non-convex** (#314). Two causes on the same
  call. The strip quads were wound counter-clockwise from outside, so a plain
  `radius 4, segments 2` bevel on a box added two back-facing polygons. And the
  arc was centred on the corner vertex, which put every intermediate point
  behind the chord between the two pulled-back edges and scooped the corner out
  instead of chamfering it, so the strip quads also came out carrying the normal
  from the far side of the bevel. The arc is centred at
  `origin + (dir0 + dir1) * radius`, which is exactly `radius` from both ends at
  any dihedral angle, and the quads are wound against the brush centre the way
  the endpoint caps already were. `radius` still means the same thing: how far
  the two faces pull back.
  - **Coverage**: `tests/test_brush_shapes.gd` sweeps every `BrushShape` for a
    face normal pointing back at the centre, skipping collapsed triangles and
    the torus, which is genuinely concave; plus the five named shapes on their
    own, the v1 migration, and a torus that must not be migrated.
    `tests/test_bevel.gd` gains outward normals, convexity at two radii, and
    each strip quad leaning towards the face it borders.
- **Four calls accepted a value they could not use and reported success.** Same
  shape each time: a number with no relationship to the geometry it modifies
  goes in, something unrecoverable comes out, and the return value says it
  worked.
  - **Bevel radius is bounded against the edge it rounds** (#315). `segments`
    was clamped at both ends and `radius` only floored, so `radius = 1e6` on a
    64 unit box returned `true` and left a brush spanning a million units while
    its own `size` still read 64. The next carve then treated an unrelated
    brush at the origin as overlapping and scattered the pieces half a million
    units away. The radius is capped at half the shorter of the two adjacent
    face extents, with a warning naming both figures, and a non-finite radius
    is refused outright.
  - **`.map` import refuses a plane it cannot read** (#318). Not for the reason
    the report gave: `float("nan")` answers `0.0` on 4.7, so `nan`, `inf` and a
    plain typo all arrived as the origin and the face read as a real plane
    through it. A coordinate token that is not a number now fails the line, and
    a coordinate past 65536 fails it too, which is what catches `1e30`. A brush
    holding an unreadable plane is dropped whole rather than built from the
    planes that did parse, because a `.map` brush is the intersection of all its
    half spaces and a missing one is a different solid, not a smaller one.
  - **Creating a displacement on a face that has one is refused** (#319).
    `init_flat()` resets distances, offsets, alphas, sew group and elevation, so
    a second press of the button threw away the terrain on that face and still
    returned `true`. `destroy_displacement()` is the deliberate way to clear
    one and it is undoable. The dock toast and the user guide say so.
  - **Displacement paint and elevation reject what they cannot use** (#320). One
    `paint()` with a non-finite centre filled all 289 distances of a power 4
    grid with NaN, which no amount of smoothing or further paint can undo, and
    it survived into the `.hflevel`. `paint()` refuses a non-finite centre,
    radius or strength, and a radius of zero. `set_elevation()` refuses a
    non-finite value and clamps the magnitude to the face's own diagonal, which
    is the only scale a multiplier on world-unit distances has to be measured
    against. Levels already saved are read through `from_dict()` and are not
    touched, so nothing changes under an existing sculpt.
  - **Coverage**: 6 tests in `tests/test_displacement.gd`, 3 in
    `tests/test_bevel.gd`, 4 in `tests/test_map_export.gd`, each with a good
    value alongside the bad one so the guards cannot start refusing what they
    should accept.
- **Deleting a hidden visgroup left its members permanently invisible** (#316).
  `remove_visgroup()` strips the membership meta from every node and then
  refreshes, but `refresh_visibility()` skipped any node that was in no
  visgroup, so every former member kept the `visible = false` it was given when
  the visgroup was hidden, with nothing left in the UI that could show it again.
  A node in no visgroup is a node nothing is hiding, so the refresh shows it.
  That covers pulling a single node out of a hidden visgroup as well.
  Committed cutters are hidden by the cut rather than by a visgroup and
  `_all_managed_nodes()` does not reach them, so they stay hidden.
  - **Coverage** (`tests/test_visgroup_system.gd`): delete a hidden visgroup,
    remove one node from a hidden visgroup, and a guard that a node still in
    another hidden visgroup stays hidden.
- **Two paint layers could be renamed to the same name** (#321). The rename
  dialog checked that the new name was non-empty and different from the layer's
  own, and nothing checked it against the other layers, so the list the user
  picks a paint target from could show the same row twice with no way to tell
  them apart. `HFPaintSystem.rename_paint_layer()` returns bool and refuses an
  empty name, an index out of range, and a name another layer already shows.
  The check sits there rather than in the dialog so a rename from anywhere is
  covered, and the dialog reports the refusal as a toast.
  - A layer with no display name shows its `layer_id`, which is the row the user
    reads, so that counts as a taken name too. Names are trimmed before they are
    compared, so padding cannot smuggle a duplicate through.
  - **Coverage** (`tests/test_paint_system.gd`): 7 tests, including renaming a
    layer to its own name, which is not a collision, and a rename to a free
    name, so the guard cannot start refusing what it should accept.
- **Valve 220 export wrote texture axes parallel to the face normal** (#317).
  Every face went out as `[ 1 0 0 0 ] [ 0 1 0 0 ]` whatever direction it faced,
  so four of the six faces of a plain box were degenerate: on a +/-X face the U
  axis was the normal, on a +/-Y face the V axis was. Valve 220 exists to carry
  per-face alignment into TrenchBroom, J.A.C.K. and the Source-lineage tools,
  and those either reject such a face or stretch the texture across it, so the
  format chosen to preserve alignment preserved nothing.
  - The cause was not a missing feature. `_auto_axes()` already picks correct
    axes per normal, but it was only reached for `CYLINDRICAL` or a projection
    outside the enum. `FaceData.uv_projection` defaults to `PLANAR_Z`, and
    `_compute_axes_from_projection()` returned `PLANAR_Z`'s `[RIGHT, UP]` for
    every face carrying it without asking whether those axes lie in the face.
    A candidate pair is now checked against the normal and falls back to
    `_auto_axes()`, which is what `BOX_UV` already did.
  - The classic Quake exporter is unaffected. It has no texture axes.
  - **Coverage** (`tests/test_map_export.gd`): all six axis directions with the
    default projection, an exported box checked line by line, and a guard that a
    +Z face keeps `PLANAR_Z`'s axes, since that is what `PLANAR_Z` is for.
### Changed
- **Non-box primitives store one face per flat surface, not one per mesh
  triangle** (#322). `_rebuild_faces()` derived the face list straight from the
  CSG mesh, so every triangle became its own `FaceData`. A cylinder was 768
  faces. A sphere was 4,224, cost 129 KB in a `.hflevel` and 424 ms to write,
  and asked the user to pick one of 4,224 slivers to put a material on a side.
  Coplanar triangles that share an edge now merge into one face before the list
  is stored, measured on this machine:

  | shape | faces | `.hflevel` bytes | save ms | create ms |
  | --- | --- | --- | --- | --- |
  | box | 6 to 6 | 1,194 to 1,194 | 17 to 17 | 1 to 1 |
  | cylinder | 768 to 66 | 16,664 to 3,629 | 81 to 19 | 6 to 11 |
  | sphere | 4,224 to 2,240 | 129,227 to 89,670 | 413 to 252 | 25 to 85 |
  | torus | 4,096 to 2,059 | 168,085 to 123,009 | 404 to 252 | 26 to 75 |

  The flat-faced shapes land on their real counts: a wedge is 5, a prism 5, a
  pentagonal prism 7, an octahedron 8, a dodecahedron 12 pentagons, an
  icosahedron 20. A 64-segment cylinder is 66, its sides plus two caps.
  - **Creating a curved primitive costs more.** A sphere goes from 25 ms to
    85 ms because the merge pass walks every triangle. That buys 161 ms off
    every save of it, and halves what undo capture, bake, validation and every
    per-face loop have to walk from then on. Positions are indexed to integer
    ids so the pass is integer lookups rather than string keys, which is what
    took it from 214 ms to 85 ms while I was writing it.
  - **Merging is conservative.** Triangles merge only when they share a plane
    *and* an edge, so two flat regions that happen to be coplanar stay two
    faces. A run whose boundary is not exactly one closed loop keeps its
    triangles rather than guessing at a surface with a hole or a pinch in it.
    Points sitting mid-edge on the boundary are dropped, which is what turns a
    cap fan back into its rim.
  - **Levels saved before this keep their old face lists**, because faces are
    serialized verbatim. They are not rebuilt on load, so nothing shifts under
    an existing material or displacement assignment. Only newly built brushes
    get the smaller lists.
  - `tests/test_hollow_tool.gd` asserted a hollow cylinder produced fewer walls
    than the brush had faces, which was true only while faces were triangles.
    One wall per distinct plane is the rule, and a face is a plane now, so it
    asserts equality.
  - **Coverage** (`tests/test_brush_shapes.gd`): the real face count of every
    flat primitive, a dodecahedron face being a pentagon, a cylinder cap keeping
    all 64 rim points, the curved shapes not losing faces, and four direct tests
    of the merge itself, including two coplanar triangles that do not touch
    staying two faces and a merged quad keeping the winding it came from.

### Added
- **CI refuses a `project.godot` that enables local tooling.** The file is
  tracked and the editor rewrites it the moment anyone enables a plugin, so a
  locally installed bridge rides into the next `git add -A`. That is how
  `addons/godot_mcp` and its `MCPRuntimeProbe` autoload got in and stayed
  enabled for months. `tools/check_project_settings.py` asserts the enabled list
  is HammerForge and nothing else, and that no autoload is registered.
  - **`override.cfg` is not a way out of this and the tool says so.** On 4.7 an
    `editor_plugins/enabled` written there does not enable the plugin in the
    editor, while the same value in `project.godot` does. Checked against
    4.7.stable with a control, since the documentation is quiet on the point.
  - **`--selftest` covers nine cases**, including the exact shape this
    repository shipped before #277, a plugin name that merely contains the
    allowed one, an enabled list the guard cannot parse, and a missing
    `[editor_plugins]` section. It runs in CI ahead of the check itself.
  - DEVELOPMENT.md now carries the `git update-index --skip-worktree` recipe for
    keeping a local enable out of `git status`, along with the pull it breaks
    and how to get out of that.
- **Create Starter is callable without the dock** (#278). The starter level was
  a dock button handler and nothing else, so tests, tool scripts and editor
  bridges had no way to build one. `HFLevelFactory.create_starter(parent)` now
  adds a `LevelRoot` and fills it with the floor, sun and player spawn;
  `HFLevelFactory.create_level_root(parent)` stops at the empty root. Both take
  an optional scene owner and an optional property dictionary, applied before
  the node enters the tree because `LevelRoot` reads its exports in `_ready`.
  The editor plugin gained `create_starter_level()` for the same result in the
  open scene as one undo entry, and the console's Create Starter action falls
  back to it when no dock is present. The dock buttons are unchanged.
  - `LevelRoot._get_editor_owner()` no longer assumes there is a `SceneTree` to
    ask, so a root built in code and not yet parented falls back to its owner
    instead of erroring.
  - **Coverage** (`tests/test_level_factory.gd`): parenting, owner resolution
    through an explicit owner and an inherited one, properties applied before
    `_ready`, a rejected null and detached parent, the reported property typo,
    the floor/sun/spawn set, child ownership so the scene saves, and a second
    call not duplicating the fixtures.
- **`tools/wait_for_ci.py` waits on the commit, not the branch.** Waiting on a
  pull request's checks by branch is the obvious thing and it is wrong: the
  newest run on a branch is often the previous one, so a merge can go ahead on a
  result that belongs to a commit nobody is merging. That happened twice while
  landing the five performance branches, once reading a superseded run and once
  reading `main`'s tip because the local checkout had drifted off the branch.
  Neither merged anything on the bad signal, but both would have.
  - **It resolves the head from the pull request every poll**, so CI's own
    published-counts commit moving the branch under it is noticed and the newer
    commit is the one graded. The head is read once more after a pass, because a
    counts push landing between the fetch and the answer would otherwise be
    reported green on the strength of the commit it replaced.
  - **A missing run is "not yet", never "passed".** Polling until nothing is
    pending cannot tell an empty check list from a finished one, which is how an
    ungraded commit looked ready to merge.
  - `--selftest` covers a run carrying the wrong commit, the wrong workflow, an
    empty list, each terminal conclusion, a head that moves mid-wait, a pass on a
    commit that was superseded in flight, and a run that never finishes. It runs
    in CI beside the placement-order selftest, since a guard that cannot fail is
    not a guard.
- **Floor Paint now carries the first room through a complete generative pass.**
  Shift+P, R, then LMB-drag lays out a walkable footprint; Y gives that last
  Brush/Rect footprint its own wall height, X/Z add grid-origin mirror copies,
  and H stamps another filled room with boundary walls from the last Rect size.
  Cross-layer strokes show live ramp/stair ghosts and Enter commits their
  `ConnectorDef`. The footprint, raise cage, and connector ghost are transient,
  stroke-local overlays; confirmed connectors persist and bake even when global
  auto-detection is off, without duplicating an automatically detected boundary.
  Inference is a default-off Paint-tab toggle whose only permitted edits are
  isolated-cell removal, one-cell cardinal hole/gap fill, and one-row/column
  corridor widening inside the dirty stroke scope. Existing Alt/Shift/Ctrl paint
  modifiers, Esc restoration, region pinning, and plain RMB camera ownership are
  preserved. A paint/mirror/room/connector confirmation is one undo; wall raise
  is a clearly chained second undo.
  - **Coverage** (`tests/test_paint_polish.gd`, `tests/test_paint_system.gd`,
    `tests/test_paint_wave2.gd`, `tests/test_auto_connector.gd`,
    `tests/test_keymap.gd`, `tests/test_shortcut_hud_layout.gd`,
    `tests/test_context_toolbar.gd`, `tests/test_plugin_gesture_recovery.gd`):
    modifiers, stable axis choice, material pick, live metrics, preview teardown,
    scoped raise and persistence, X/Z mirroring, room stamping, connector
    detection/confirmation/bake deduplication, opt-in cleanup limits, one-entry
    undo boundaries, no RMB handler, lost-release recovery, region reload,
    keymap discovery, and Paint context controls.
- **Re-hollow says what it would rebuild over.** Pressing Re-hollow deletes every
  wall and shells the recorded solid again. A wall you had moved, resized,
  retextured or painted went with the rest of them, without a word — the one thing
  the live-hollow pass shipped knowing was missing.
  - The record now keeps **the shape each wall was made as** beside where it was
    put. That is the only thing that could tell a reworked wall from a fresh one:
    the walls are not copies of each other, so there is nothing to group them
    against the way the array groups its copies. It is
    `HFDuplicator.shape_signature()`, made public rather than written twice — values
    only, serializable, and blind to weight-image contents for the cost reason
    recorded beside it.
  - **Movement is read against what a re-shell would actually do.** When the walls
    agree on one move the room has been relocated, the re-shell follows it, and
    nothing is counted. When they disagree the rebuild goes back to the recorded
    placement, so any wall standing anywhere else is about to be moved back, and
    that is the count.
  - The Hollow row names the number and names **Detach** in the same sentence, and
    Re-hollow has to be pressed twice. The agreement is keyed on the hollow and the
    thickness, so changing the number earns the warning again — you agreed to one
    re-shell, not to all of them.
  - Records written before either field answer "cannot tell" for that half, so an
    older level loads and re-shells with nothing to migrate.
  - **Coverage** (`tests/test_hollow_edit_warning.gd`): 25 tests over a moved wall,
    a resized wall, a repainted wall, a wall that is both, a room relocated and a
    room turned counting nothing, a relocated room with one wall pushed further, a
    deleted wall, an unknown hollow, an old record, a restored hollow, the first
    press refused, the second going ahead, a changed thickness earning it again,
    and Detach clearing it.
- **A hollowed brush can be shelled again at a different thickness.** Hollow was
  the last operation with no way back to its own numbers short of Ctrl+Z: it
  replaced a solid with walls and forgot the solid, so a room whose walls came out
  too thin could only be undone.
  - Selecting any wall turns the Hollow row into an editor for that hollow: its
    own thickness, **Hollow** becomes **Re-hollow**, and **Detach** appears beside
    it. The same shape the Structure and Duplicate Array sections already had.
  - **The record keeps the solid**, which is the one thing that could not be
    recovered from the walls themselves.
  - **The walls are only replaced once the new ones are known good.** A re-shell
    rebuilds the solid and plans the new walls on it *before* touching the old
    ones, so a thickness the brush cannot take leaves the level exactly as it was.
  - **A room dragged across the level re-shells where it now stands.** Each wall
    sits at its own centroid rather than at the solid's origin — the first attempt
    assumed otherwise and rebuilt the room back where it was made, which a test
    caught — so the record keeps where each wall was put and the move is read from
    the delta they share. Walls moved one at a time disagree, which is editing
    rather than relocating, and the placement stays. A record written without wall
    placements answers "no move", so nothing needs migrating.
  - `HFTransformSystem.same_transform()` is now the one definition of "these two
    transforms are the same place", read by the hollow's walls and the array's
    copies both.
  - **Coverage** (`tests/test_live_hollow.gd`): 27 tests over the record, the
    re-shell, the refused thickness that costs nothing, relocation by drag and by
    turn, walls moved one at a time, detach, the row becoming an editor, repeat
    presses without reselecting, undo, and what survives a state restore.

### Changed
- **No editor bridge is vendored here any more** (#277). The repository shipped
  a copy of Godot MCP Native in `addons/godot_mcp` and enabled it in
  `project.godot` for everyone. That was one contributor's tooling, it had
  nothing to do with the plugin, and having it sitting there enabled made the
  project look wired to a bridge it was not wired to. It is gone, along with its
  autoload, its setup guide, and the token and port instructions that went with
  it. Install whichever bridge you use into your own `addons/` folder.
  - **`addons/` is an allowlist in `.gitignore`**, so a bridge dropped in there
    stays untracked. `project.godot` is tracked and cannot be covered that way,
    so enabling a plugin locally is a change to keep out of a commit by hand.
    The pull request template asks about both.
  - **`tools/capture_ui.py` cuts `project.godot` back to the HammerForge plugin
    alone** for a capture, rather than removing one named addon. Naming them
    went stale the moment the named one was not the one you had enabled.
  - **The release guard fails on any `addons/` folder that is not
    `addons/hammerforge`**, instead of checking a list of the ones someone
    thought of.
- **Check Issues spends its time on the level, not on building strings.** The
  micro-gap and non-manifold scans key their spatial grid on the position of
  every vertex and every edge. Those keys were formatted strings, and
  `_cell_keys()` built **twenty-seven of them per vertex** so a pair straddling a
  cell boundary would still be found. At 76 microseconds a call, once per vertex,
  that was very nearly the whole pass.
  - **The keys are grid indices now.** A cell is a `Vector3i`, its neighbours are
    plus or minus one, and an edge is the pair of cells its ends fall in with the
    smaller end first. Nothing is allocated to look a point up.
  - **The buckets are the same buckets.** The index is the snapped position
    divided by the step, with `snapped()` still in the middle, so the grid has not
    moved and the same levels report the same issues.
  - Measured over 1,000 brushes: a full `check_bake_issues()` went from 1,835.8 ms
    to 460.4 ms. Per 20,000 calls, `_cell_keys()` went from 1,520.8 ms to 157.8 ms,
    `_snap_key()` from 57.8 ms to 11.1 ms, and `_edge_key()` from 74.4 ms to
    23.2 ms.
  - **Coverage** (`tests/test_validation_cell_keys.gd`): 12 tests over the
    tolerance, negative coordinates, the index matching the snapped position it
    replaced, the twenty-seven distinct neighbours, a point finding its own cell,
    a neighbour across a boundary, edge symmetry, fixed edge precision against a
    raised weld tolerance, and both key kinds actually colliding as dictionary
    keys rather than merely comparing equal.

- **Precision snap stops measuring brushes the pointer cannot reach.** With
  Vertex, Center, Edge or Perpendicular on, every pointer motion transformed
  every vertex of every brush in the level into world space, appended the lot,
  and only then measured them against `snap_threshold`. A brush on the far side
  of the map did the same work as the one under the cursor, so the cost tracked
  the size of the level rather than how much of it was in reach.
  - **A brush is now measured against the query point before any of its snap
    points are built.** The check is the brush origin against the query, allowing
    for how far the brush's own box reaches once its rotation and scale are
    applied, so a long wall whose origin is a hundred units away is still kept
    while its far end is under the pointer. Edges lie between vertices inside
    that reach, so Perpendicular is covered by the same bound.
  - **The extent is read without building the snap points**, because building
    them is the work being skipped. It follows the same branch as the geometry
    itself, and tests hold the two to the same answer for a box, a custom brush,
    a wedge and a brush with no faces.
  - **The bound is exact for any transform**, including a mirrored or sheared
    one, because it sums each axis's contribution to the furthest corner rather
    than assuming the basis is a rotation.
  - Measured over 300 brushes and 200 motion events with Vertex, Edge and
    Perpendicular on, one brush in reach: an all non-box level went from 2.40 ms
    to 0.86 ms per event, and a level of boxes from 2.63 ms to 0.44 ms. The
    non-box figure still carries a cache lookup per brush, which is the snap
    geometry cache's key and not this change.
  - **Coverage** (`tests/test_snap_candidate_culling.gd`): 20 tests over a
    distant brush contributing nothing, three hundred of them changing nothing,
    a distant centre, an unlimited query still collecting the level, a long wall
    reached by its far end, perpendicular snap onto a long edge, a turned brush,
    a scaled brush, a custom brush, exclusions, the preview brush, closest
    candidate ordering, a point out of reach of everything, what a pointer query
    actually measures, and the two extent branches agreeing.
- **Check Issues stops comparing brushes that are nowhere near each other.** The
  two subtraction checks each did their own broad scan. `_check_floating_subtract()`
  walked the whole brush list for every subtraction looking for an additive to
  land on, `_check_overlapping_subtracts()` then compared every subtraction with
  every other one, and both rebuilt each brush's AABB inside those loops. On a
  level of 500 solids and 500 cuts that is 250,000 pair tests and 500,000 boxes
  built, almost all of them between brushes on opposite sides of the map.
  - **One broad phase now answers both questions.** Every world AABB is built
    once, then a single sort-and-sweep along the axis the level is widest on
    visits only the pairs that overlap on that axis. A cut is grounded when the
    sweep pairs it with a solid, and two cuts that meet are an overlap, so the
    same walk produces both results.
  - **The axis is chosen from the brushes**, not fixed, because a level is usually
    a floor plan and the axis that separates the most brushes is the one worth
    sorting on.
  - **The box is still the brush's own size at its origin, rotation and all.**
    Widening it to a turned brush's real extent would change which levels report
    an issue, and that is a different question from this one.
  - **What gets reported has not moved.** Floating cuts are still listed in level
    order among the other per-brush issues, and overlapping pairs still name the
    earlier brush first and carry it as the issue's node.
  - Measured over 1,000 brushes with the checks timed on their own: a floor plan
    went from 117.51 ms and 250,000 pair tests to 11.26 ms and 21,248, and the
    same brushes strung out along a line went from 114.26 ms to 4.85 ms and 500
    pair tests. The rest of `check_bake_issues()` is untouched and still the
    larger share of the pass.
  - **Coverage** (`tests/test_bake_issues_scale.gd`): 18 tests over a cut inside a
    solid, a cut that only touches one, a solid in the committed node, entity
    solids and entity cuts, a turned cut, a solid that sorts after its cut on two
    different axes, a long corridor reaching a cut far from its origin, three and
    twelve mutually overlapping cuts, pair naming and ordering, and comparison
    budgets over spread out and strung out levels.
- **The Performance section stops measuring the level when nobody is looking at
  it.** It refreshed every thirty editor frames whether it was open or shut, and
  it is created shut. Those readouts are not label assignments: the vertex
  estimate walks every brush and every face, the paint figure walks every layer,
  and with chunking on the chunk count recollects the whole bake candidate set,
  builds the chunk dictionary and sorts it while the recommendation measures the
  level bounds all over again. The levels that make that expensive are the ones
  that make the panel worth opening, so an idle editor on a big chunked scene was
  paying the most for numbers on screen nowhere.
  - **Collapsed, on another tab, or in a hidden dock all count as not looking.**
    Leaving the section open on the Manage tab and working on the Build tab is
    the common case, and it used to cost the same as watching it.
  - **Opening the section fills it in at once** rather than showing whatever the
    last look left behind until the next tick.
  - The **Live Brushes** count in the footer is on screen at all times and still
    refreshes on the same tick. It reads a cached count, so it was never part of
    the cost.
  - **Coverage** (`tests/test_perf_panel_visibility.gd`): 8 tests over the section
    starting shut, a shut section left alone across ninety frames, the footer
    still counting, opening, an open section refreshing, closing again, an open
    section on a tab nobody is on, and coming back to that tab.
- **The entity wiring overlay only redraws when the wiring changes.** It rebuilt
  every ten editor frames whether or not anything had moved: the connection list
  was recollected, every target was resolved by scanning the whole level, the
  curve mesh was thrown away and rebuilt, and Highlight Connected freed and
  remade its pulse spheres. On a level with 200 entities and 400 outputs that is
  about 80,000 name comparisons per rebuild, six times a second, to draw the
  picture that was already on screen.
  - **Targets resolve through one index instead of one scan each.**
    `HFEntitySystem.build_name_index()` maps every address in the level to the
    nodes that answer to it in a single pass, and the drawing loop reads it. The
    addresses and their order match `find_entities_by_name()` exactly, and they
    are built next to it so the two cannot drift apart.
  - **The redraw is guarded by a change check rather than by a signal.** A rename
    in the Scene dock, an undo, and an entity dragged in the viewport all change
    the picture without going through HammerForge, so a signal would have had to
    be emitted from each of them and the ones nobody remembered would be
    stale-overlay bugs. The check reads each node once; the rebuild it guards
    reads every connection against every entity.
  - **Pulse spheres are moved rather than freed and remade**, and the pulse now
    advances on the real frame time instead of an assumed 60 frames per second.
  - **A graph where every connection dangles no longer opens an empty mesh
    surface.** Renaming the last live target left the overlay closing a surface
    with no vertices in it, which Godot reports as an error. Nothing resolves, so
    now nothing is drawn.
  - **Coverage** (`tests/test_io_visualizer_dirty.gd`): 28 tests over idle frames,
    an output added, removed and re-delayed, a native rename, an alias edit, a
    moved entity, a moved brush entity, an entity added and removed, selection,
    a forced rebuild, a lost mesh node, sphere reuse and release, the real delta,
    the dangling-only graph and its recovery, and the index against the lookup it
    replaces.
- **The array edit warning counts more than movement.** It counted a copy that had
  been dragged and said nothing about one that had been resized, reshaped,
  retextured, or had a paint layer added — though the same press rebuilds over
  both. Both are counted now, and the sentence says "edited by hand" rather than
  "moved by hand".
  - Read as a vote again, and grouped rather than compared against the source:
    paint the original and every copy differs from it at once, which is the source
    having changed rather than anybody editing copies. Copies that still agree
    with each other are the array; a copy on its own is the edit.
  - **The comparison is values only, with no resource identity.** Reusing
    `HFBrushChangeTracker._signature()` looked right and was not: each copy holds
    its own equal-but-separate `FaceData` and its own weight image, so a signature
    carrying identity reported 199 of 200 copies as edits. That signature is
    correct for its own question — whether one brush has changed since it was last
    looked at — and wrong for this one. Found by measuring rather than by reading.
  - **Weight-image contents are deliberately left out.** Hashing every texel of
    every face of every copy measured 127 ms over a full-budget array against
    22 ms without, on an event that fires whenever the selection changes. A layer
    added, removed, retextured or resized is noticed; painting inside an existing
    one is not. The full check over 200 fully-painted copies measures 27.9 ms.
  - Nothing new is recorded, as with the move: the comparison is between the
    copies themselves.
  - **Coverage** (`tests/test_array_edit_warning.gd`): 9 more tests, including a
    resized copy that has not moved, a repainted one, a copy that is both, a layer
    added to one copy, two copies reshaped alike, a repainted original, and the
    painted-array regression the measurement exposed.

- **The six preview overlays share one base instead of six copies of it.** Hollow,
  carve, clip, subtract, structure and array each owned a container node, a set of
  `MeshInstance3D`, a ghost material and a teardown, and each wrote all four out
  again. Two called the container `_container` and four called it
  `_preview_container`. That duplication is what let four of them drift into
  placing their meshes in the wrong space — each was fixed on its own, because
  there was nowhere to fix it once.
  - `HFPreviewSystem` extends `HFSystem` and owns the container lifecycle, the
    mesh pool, `ghost_material()`, `clear()`, `set_enabled()` and `destroy()`.
    What stays with each preview is what actually differs: what it draws, what
    colour it draws in, and how it decides there is nothing to draw.
  - **The third copy of `line_mesh` is gone.** Carve, clip and hollow each carried
    a private `_lines_mesh()` static identical to `HFOutlineUtil.line_mesh()`.
  - `_ensure_container()` stays overridable, because clip makes three named meshes
    rather than an indexed pool — but the base reaches the container through a
    non-virtual `_build_container()`, so an override that makes meshes cannot be
    re-entered by the making of them.
  - Subtract keeps its own `set_enabled()`: it connects and disconnects signals on
    the way in and out, so unlike the others it has to know it is already enabled.
  - Six previews: 1,249 lines to 1,006. With the 122-line base, 121 lines fewer
    overall.
  - **Behaviour is unchanged**, and the suite reports the same counts either side
    of the refactor. **Coverage** (`tests/test_preview_system.gd`): 16 tests over
    the material, the container, the pool, clearing, enabling and teardown,
    including a drift guard that fails if two previews ever name their container
    the same thing.

### Added
- **An Update to an array now says what it would undo.** A copy can be dragged
  somewhere on purpose; Update put it back without a word, and Detach sat beside
  the button as the way out — but a choice you do not know you are making is not
  a choice.
  - The section counts the copies a rebuild would move and says so, naming the
    number and naming Detach. Update then asks a second time before doing it, the
    way the Structure section asks before rebuilding over painted faces.
  - **The reading is a vote**, the same shape as the structure records' relocation
    vote and for the same reason: a source that has been dragged leaves every copy
    needing the same move, and calling that twelve hand edits would be a lie. The
    move most copies agree on carries the array; the copies that disagree are the
    edits. A source that moved is said separately — *"The original has moved.
    Update will bring the copies over to follow it."* — and does not stand in the
    way of the button, because following the original is what an array is for.
  - **Nothing new is recorded.** `expected_copy_transforms()` recomputes where each
    copy would be rebuilt from the live sources through `placements_for()`, the
    arithmetic the ghost and the button already share. No new `.hflevel` field, no
    migration, and a reading that cannot go stale. It answers with nothing when the
    copies and the sources no longer pair up, because guessing the pairing would
    report every copy in the level as moved.
  - The second press agrees to one particular rebuild: changing the numbers after
    the warning earns it again, and Detach clears it.
  - Not covered: a copy that was resized, reshaped or repainted rather than moved.
    Telling would need a signature recorded per copy, and it cannot be taken
    cheaply — `FaceData.to_dict()` PNG-encodes every paint weight image.
  - **Coverage** (`tests/test_array_edit_warning.gd`): 21 tests over the vote, the
    moved-source reading, a source moved *and* a copy dragged, float noise below
    the threshold, the messages, and both presses.

- **An array you made is an array you can change your mind about.** A structure
  could be reselected, retuned and rebuilt; an array could only be created and
  deleted. The numbers that laid one out were already recorded and already
  serialized in the `.hflevel` — nothing ever read them back.
  - Selecting any piece of an array turns the **Duplicate Array** section into an
    editor for it: its layout, its own numbers, **Create Array** becomes **Update
    Array**, and **Detach** appears beside it. This is the same shape the
    Structure section already had, so the two surfaces now answer a selection the
    same way.
  - **Either the source or any copy will do.** `get_duplicator_for_brush()` only
    ever resolved the `duplicator_id` on a source brush, and the sources are
    buried under the ring or the lattice they seeded, so the piece you can
    actually click on reached nothing. It reads `duplicator_instance_of` as well
    now, which is also why **Remove Array** no longer answers a clicked copy with
    "not a duplicator source".
  - **Update rebuilds rather than moves**, because a change of layout or of count
    changes how many copies there are. The array keeps its id across the rebuild,
    so it can be tuned again without reselecting — the first Update frees the copy
    that was selected, and the section holds on to the array rather than falling
    back to Create at the one moment it must not.
  - **A ring keeps its own centre.** The pivot of an array being edited comes from
    its record, not from the selection: taking it from the selection would send
    the whole ring over to whichever copy was clicked the moment its count moved.
  - **Detach keeps the copies and forgets the array**, for when the layout has
    given you what you needed and you want to edit one copy on its own. Update,
    Detach and Remove are the three different answers, and they now sit together.
  - The 256-brush budget is asked before the rebuild, so an update that would blow
    it is refused with nothing deleted.
  - A brush info carries neither duplicator tag, so a state restore re-tags the
    copies as well as the sources; without that an undo left an array whose pieces
    no longer said what they belonged to.
  - A rebuild that produced nothing answers no rather than yes. Nothing cleans a
    duplicator record when a brush is deleted, and the layout calls report having
    run rather than having produced anything, so an array whose sources have since
    been deleted is dropped instead of left offering Update on nothing.
  - **Coverage** (`tests/test_live_arrays.gd`): 31 tests over resolution from a
    copy, the section becoming an editor and going back, all three layouts loading
    their own controls, rebuild, repeat rebuild, layout change, pivot stability,
    the refused-over-budget path, the deleted-source path, detach, remove from a
    copy, undo, and what survives a state restore.

### Fixed
- **Undo snapshots no longer share mutable state with the live level** (#282).
  `HFStateSystem` handed the live containers to the snapshot on one side of two
  pairs: capture aliased `MaterialManager.materials`, and restore handed the
  snapshot's own `face_selection` dictionary back as the live selection. Each
  pair was already guarded on its other side, so the shape was easy to miss. A
  palette edit after a capture wrote into the snapshot, and undo could not put
  back the material it was taken to protect. Both sides now copy.
- **Loading a `.hflevel` restores the material palette again** (#283).
  `LevelRoot.set_materials()` assigned an untyped `Array` into the
  `Array[Material]` the manager exports. Godot 4 rejects that, so the write was
  skipped and nothing checked the result: the editor kept whatever palette it
  already had while the saved one was dropped, and every face `material_idx`
  from the file then indexed into the wrong palette. The array is converted
  first. Slot positions are preserved and a slot that does not hold a Material
  comes back as null with a warning naming the index, because compacting would
  repoint every face above it.
- **Terrain slot paths survive a load** (#284). The same untyped-into-typed
  assignment in `HFPaintSystem.restore_paint_layers()` dropped
  `terrain_slot_paths`, `terrain_slot_uv_scales` and `terrain_slot_tints` on
  every `.hflevel` load. `_ensure_terrain_slots()` ran straight after and
  refilled the four slots with defaults, so a loaded layer came back pointing at
  no textures with nothing to say why. Checked against 4.7.stable: the engine
  rejects the assignment for all three, not only the paths.
  - **Coverage** (`tests/test_state_snapshot_isolation.gd`): a palette edit after
    a capture, a selection edit after a restore, an untyped palette replacing a
    live one, an empty payload clearing it, a junk slot kept in place, and a
    terrain slot path round trip. All six fail on the previous code.
- **Removing a palette material no longer repaints the brushes above it**
  (#285). `FaceData.material_idx` is a plain index into
  `MaterialManager.materials`, and removal compacted that array without touching
  the faces pointing into it, so deleting the first material repainted every
  brush that used a later one and any face on the last slot pointed past the
  end. `remove_material_from_palette()` now shifts every index above the removed
  slot down and sets faces that used the removed slot to unset, walking the same
  managed-brush traversal that identity work uses so committed cutters are
  covered too. An out-of-range index is a no-op rather than a signal.
- **Refresh Prototypes is a refresh again** (#298). The button appended all 150
  prototype materials every time it was pressed, so a second click gave a
  300-entry palette with every name twice, and the palette is saved with the
  level. `HFPrototypeTextures.load_all_into()` skips a pattern/colour already in
  the palette, keyed on `resource_path`, and returns the number actually added,
  so a second call returns 0. `LevelRoot.add_prototype_materials()` calls it
  rather than keeping a second copy of the same loop.
  - **Coverage** (`tests/test_material_palette_integrity.gd`): a face following
    its material down a slot, a face whose material was removed, a face below the
    removal, an out-of-range index, a second prototype load adding nothing,
    unique names after two loads, and a hand-made material keeping slot 0.
- **A bad array count no longer deletes the array** (#299). `regenerate()` called
  `clear_instances()` before asking whether the new numbers produced anything, so
  typing 0 into an array's count threw the copies away and then reported failure.
  `update_duplicate_array()` read that failure as "the copies are gone, so the
  record is dead" and erased the record, leaving the array unreachable: a good
  count afterwards returned false, and so did detach. The check now runs before
  the teardown, on both sides, so a count the layout cannot use is a no-op with
  the copies still standing and the record still there to correct. The erase is
  kept for the case it was written for, which is every source brush deleted.
- **The 256-copy ceiling holds on every path** (#300). `can_generate()` was
  called only from the dock's linear-create button, so `create_grid_array()` and
  `update_duplicate_array()` walked straight past it: a 12-cubed grid built 1728
  brushes and reported success, and an array created inside the cap could be
  raised to any size afterwards. The check now sits in `generate()`,
  `generate_radial()`, `generate_grid()` and `regenerate()`, and in the three
  `create_*` methods on `HFBrushSystem` ahead of `_new_duplicator_for()` so a
  refusal cannot take the array the user already had with it. The dock keeps its
  early check for the message it shows before the user commits.
  - `HFDuplicator.grid_copy_count()` and `requested_copy_count()` work out how
    many copies a layout would make without building it, which is what lets the
    refusal land first. Both agree with `placements_for()`, and a test pins that.
  - **Coverage** (`tests/test_array_limits.gd`): a refused update leaving copies,
    record, correction and detach intact, an update refused at the cap, a grid and
    a radial array over the cap, a grid under it still building, a refused create
    not disturbing the existing array, and the copy count matching the placements.
- **`.map` export writes the face's material, not `__default`** (#286). Every
  face line used the module constant, so a level with a full palette exported to
  a file where every face read `__default` and importing it back gave every face
  slot 0. The name now comes from the palette through `face.material_idx`, with
  `__default` kept for an unset or out-of-range index. Import reads the texture
  token off the face line and maps it back to a palette slot by name.
  - The texture field is positional and whitespace delimited, so a name with a
    space in it would be read as the name plus the start of the UV numbers.
    `MapIO.texture_token()` collapses whitespace to underscores, and import
    matches on the same token.
  - A name the palette does not hold leaves the face unset. A `.map` names a
    texture without saying where it lives, so adding a material would mean
    putting a guessed resource path on the face.
  - Box brushes build their own faces, so their textures travel keyed on the
    plane normal and are matched to the faces the box makes. Everything else
    lines up index for index against the hull polygons, which carry the plane
    they came from.
  - **The UV tail carries the face's numbers** in both adapters. Classic Quake
    has no texture axes, but it does have an offset, a rotation and a scale, and
    it was writing `0 0 0 1 1` into all five.
- **A cylinder exports `sides + 2` planes instead of `3 * sides`** (#291). The
  caps were walked as a triangle fan and a plane written per wedge, but a `.map`
  brush is an intersection of half spaces and every wedge of a flat cap lies in
  the same plane. A 16-sided cylinder went out as 48 planes, 30 of them exact
  duplicates of two, which is what several external compilers report as a
  degenerate brush. Each cap is now one plane taken from three points on its
  ring.
  - The cylinder writer also wrote its planes facing inward, which the format
    notes already promised it did not. Its walls and caps now face outward like
    the box and custom-face writers. Import tried both orientations, so this was
    invisible until the file reached another tool.
  - Face data for a cylinder plane is found by normal rather than by counting.
    Curved primitives take their faces from the mesh, so the old index walk was
    assuming a face order the mesh generator does not promise.
  - **Coverage** (`tests/test_map_face_fidelity.gd`): an assigned material on
    every face line, an unset and an out-of-range index, the whitespace token, the
    UV tail, the plane count at three side counts, no two planes coincident, every
    plane facing outward, a whole-brush and a per-face round trip, and a texture
    the palette does not hold.
- **Four loaders stop trusting the payload they are handed.** Each sits behind a
  file that can be hand edited, synced between machines or truncated mid write,
  and in each case a bad value did not fail where it was read.
  - **A displacement face comes back flat rather than half restored** (#290).
    `HFDisplacementData.from_dict()` took the power on trust and sized the arrays
    from the payload, while `get_dim()` and every read assume the two agree. A
    mismatch sent each `row * dim + col` to the wrong cell, and because
    `set_distance()` and `add_noise()` both guard on `idx < size()`, the writes
    past the end were dropped in silence. The power is clamped the way
    `init_flat()` clamps it, each array is checked against the vertex count that
    power implies, and a mismatch is a warning naming both numbers.
  - **A typo in the keymap file no longer errors on every keystroke** (#292).
    `HFKeymap.load_or_default()` accepted whatever JSON was there, so a value of
    the wrong type errored inside `matches()`, which runs on every key event in
    the viewport, with a message naming `hf_keymap.gd` rather than the file the
    user actually got wrong. Entries that are not dictionaries, entries with no
    usable `keycode`, and keys that are not HammerForge actions are reported once
    on load, naming the file and the key, and the default is used instead.
  - **A wrong-typed generator setting comes back as a result** (#293).
    `HFGeneratorSchema._coerce()` called `int({})`, which is not a valid
    constructor call: it errored, evaluated to null, and the null was written into
    the settings. From there the builder's `validate()` never returned,
    `HFGeneratorSystem.create()` read `.ok` off nothing, and
    `LevelRoot.create_generator()` handed back null from a function declared
    `-> HFOpResult`. `_coerce()` is total now, falling back to the field's default
    with a warning; a numeric string still counts as a number. `validate()` also
    treats a null builder result as a failure, so no future builder can put a
    null back into that path.
  - **One junk preset no longer empties the preset list** (#294).
    `HFIOPresets.load_presets()` tested only that the file parsed to an Array, so
    `[1, 2, 3]` was accepted and `get_all_presets()` then errored on the first
    element and returned nothing, dropping the real presets below it. Elements
    are kept only if they are dictionaries with a name and a connections array,
    and a rejection names the file and the index. `add_user_preset()` refuses an
    empty name and returns whether it added anything, so a bad entry cannot be
    made from inside the editor either.
  - **Coverage** (`tests/test_untrusted_payloads.gd`): 16 tests over all four,
    including a good value on each path so the validation cannot start refusing
    what it should accept. Twelve fail on the previous code.
- **A connection reports its source under the name it is addressed by** (#288).
  `HFEntitySystem.get_all_connections()` built the source side from the scene
  tree name and the target side from the stored output, which is the authored
  `entity_name`, so the two halves of every record were in different namespaces.
  For a brush entity the tree name is whatever Godot generated, so a source never
  matched an authored name and `get_connection_summary()` reported every wired
  entity as triggering nothing. `source_name` is the authored name when there is
  one and the node name otherwise, `source_node_name` carries the other, and the
  summary answers to either address rather than making the caller know which one
  it is holding.
- **`.map` export carries entity names and I/O outputs** (#287). The authored
  name and the `entity_io_outputs` metadata were never read, on point entities or
  brush entities, so a level wired up in the Objects tab exported inert. The
  authored name is written as `targetname`, and each connection is one key/value
  line with the output name as the key and
  `target,input,parameter,delay,fire_once` as the value, which is the order
  Hammer writes a VMF connection. `parse_map_text()` reads them back.
  - **No connections block.** A `.map` entity body is key/value lines and nothing
    else: a nested brace inside an entity is read as a brush by every parser
    including this one, so a Source style block would not survive its own round
    trip.
  - **One line per connection**, so two outputs on the same event both reach the
    file. The parser now keeps the key/value lines in file order alongside the
    properties dictionary, which would otherwise keep only the last of a repeated
    key.
  - **Wiring is told apart from settings by shape, not by a naming rule.** A line
    is read as a connection only with five comma-separated fields, a numeric
    delay, and a target and input that are there. An imported output does not
    also land in `entity_data`.
  - **Coverage** (`tests/test_entity_names_and_io.gd`): the source namespace, the
    summary from either address, an entity with no authored name, the value shape
    both ways, four ordinary properties that must not read as connections, both
    entity kinds exporting, two outputs on one event, an unwired block gaining
    nothing, and a round trip for each entity kind.
- **Numeric dimension entry accepts the keypad** (#297). `KEY_KP_0` through
  `KEY_KP_9` and `KEY_KP_PERIOD` were not handled anywhere, while `KEY_KP_ENTER`
  was accepted in six places including the commit key right below the digit
  check. So typing a size on the keypad mid-drag put nothing in the buffer, and
  then keypad Enter ended the gesture at whatever size the mouse happened to be
  at. The half that worked made the half that did not look like the tool had
  ignored the number rather than never having received it. Mapped by keycode
  rather than by reading numlock, since with numlock off these keys arrive as
  arrows and never reach the handler.
  - **Coverage** (`tests/test_plugin_numeric_input.gd`): a keypad-typed decimal
    driving the preview, `KEY_KP_0` at the far end of the range, keypad Enter
    committing a keypad-typed value, and one decimal point whichever key typed it.
- **Renaming a visgroup onto an existing name is refused** (#296).
  `HFVisgroupSystem.rename_visgroup()` guarded an empty name, an unchanged name
  and a missing source, but not the target already existing. Renaming A to B when
  B existed overwrote B's record, colour and visibility and all, then rewrote the
  name on every node that carried A, so two memberships silently became one. The
  loss showed up later rather than at the time: B's members were hidden, B's
  record was gone, and the next `refresh_visibility()` made them visible again
  with nothing to say why. It returns whether the rename happened, so a rename
  field can say the name is taken. Merging two visgroups is a different
  operation, and one somebody should have to ask for.
  - **Coverage** (`tests/test_visgroup_system.gd`): a refused rename leaving both
    records, both memberships and B's hidden state alone, plus the return value
    across a working rename, a missing source and an empty name.
- **The bake dry run counts what the bake will actually take** (#295).
  `count_brushes_in()` counted container children and checked neither the cordon
  nor `bake_visible_only`, while the bake checks each of them in seven places. So
  the preflight, which is the thing that tells a user what a bake is about to do,
  reported brushes the bake was going to skip: a cordon with one brush inside it
  and one outside reported two and baked one. A single `brush_bakes()` predicate
  now answers the question, and the two `_container_has_effective_*` loops ask it
  too, so the counting and the baking cannot drift apart again. Subtraction is
  deliberately not part of it, since a subtractor is a brush the bake takes and
  uses, and pending cuts get their own line in the dry run.
  - **Coverage** (`tests/test_bake_system.gd`): a brush outside the cordon, a
    hidden brush under Bake Visible Only, a fully cordoned out level reporting no
    chunks, and both filters off still counting everything.
- **A brush cannot be created at a zero or negative size** (#289).
  `create_brush_from_info()` took `info["size"]` as given, and it is the single
  door into the level for undo restore, duplication, prefab instancing, `.map`
  import and `.hflevel` load. A negative component gave the basis a negative
  determinant, which inverts the face winding invisibly: every `FaceData` ended
  up with a normal pointing the opposite way from the vertices it holds, which
  only shows at bake or in an exported plane. A zero component gave a brush with
  no volume. Both landed in the draft container with an id and counted as live.
  Each component is now taken as its magnitude and floored at 0.1, the same
  figure the validator's auto fix uses, with one warning naming the size that was
  asked for and the one used.
  - **The validator tells the two apart.** A negative size was being reported as
    a "Zero-size brush", which sends the reader looking for the wrong thing. It
    reads "Inverted brush" now, and a genuine zero extent still reads
    "Zero-size brush".
  - **Coverage** (`tests/test_brush_size_guard.gd`): a negative size building the
    right way out with a positive determinant, every face normal agreeing with
    its own winding, a zero size, a partly zero size moving only the bad axis, a
    good size passing through untouched, a size that is not a Vector3, and both
    validator messages.
- **Erasing paint gives the memory back** (#301). `HFPaintLayer.set_cell()`
  allocated a chunk on demand and never released one, so clearing the last cell
  in a chunk went down the same path as setting one. `remove_chunk()` sat
  directly below it with no callers, and the only reclamation in the file was
  region streaming eviction, which is unloading rather than erasing. A chunk is
  dropped when its last bit clears, so `get_paint_memory_bytes()` goes back down
  and painting an area to try it out and erasing it does not leave a level file
  bigger than one that was never painted.
  - `HFChunkData` keeps a live-cell counter, so "is this chunk empty" is a
    comparison rather than a scan of every byte on each erase. It is recounted
    whenever the bitset is written whole, which is what a load does.
  - **The chunk is dropped before the dirty mark, not after.** `remove_chunk()`
    clears the dirty flag too, and the reconciler needs to see the chunk to take
    its geometry away. Region eviction reconciles removed chunk ids the same way.
  - **`HFStateSystem.capture_paint_layers()` skips an empty chunk**, so one that
    was created and never filled cannot reach a `.hflevel` save or an undo
    snapshot carrying its bits, material ids and three blend weight arrays for
    paint that is not there.
  - **Erasing no longer allocates.** `set_cell()` went through
    `_get_or_create_chunk()` on the way out as well as in, so a stroke over
    unpainted ground built chunks full of zeros. Erasing looks the chunk up
    instead.
  - **Coverage** (`tests/test_paint_chunk_reclaim.gd`): chunks returned and paint
    memory back to zero after an erase, a chunk with one cell left kept, a
    dropped chunk repainted, erasing unpainted ground, an erased layer
    serializing nothing, a painted one still serializing, paint surviving a
    capture and restore, and the live count after a wholesale write.
- **A prefab could wire its copy's outputs to the entities it was built from.**
  `HFPrefab.instantiate()` remapped I/O by turning each old node name into the new
  one and then looking that name back up. The lookup resolves an authored
  `entity_name` as well as a node name, so an entity of the same prefab whose
  authored name matched a later one's generated node name was returned first: it
  was remapped twice, and the entity it stood in for was never remapped at all and
  kept its outputs aimed outside the instance. The prefab looked right in the scene
  tree and its wiring was wrong.
  - It already had direct references to every entity it had just created. The
    remap walks those instead, so each is remapped exactly once and no name lookup
    is involved.
  - **Coverage** (`tests/test_prefab.gd`): a two-entity prefab whose first entity
    is renamed on the way in and carries an authored name matching the second one's
    node name, asserting the second one's output lands inside the new instance; and
    the ordinary case with no alias in the way. The first fails against the old
    code, keeping the output aimed at the entity the prefab was built from.
- **Deleting a named entity left the connections that used its authored name.**
  An entity has two addresses — its node name and its authored `entity_name` — and
  an output can be aimed at either. Deletion only ever cleaned up the node name, so
  a connection aimed at the alias stayed on its source, pointing at nothing, and
  would quietly start addressing an unrelated entity the moment somebody reused the
  name.
  - Both are cleaned now, through one `cleanup_connections_for_deleted()`.
  - **A name some other live node still answers to is left alone.** Duplication and
    prefab placement both produce two entities sharing an authored name, and
    cutting the survivor's connections would be worse than the bug being fixed. The
    check is deliberately wider than `find_entities_by_name()`, which resolves a
    brush entity by node name only though the runtime also uses its authored name:
    being wrong there only ever keeps a connection.
  - **The brush side had the same defect** and has had it longer, since brush
    entity names started persisting in #149. Same helper, called from
    `_cleanup_brush_references()`.
  - **Coverage** (`tests/test_reference_cleanup.gd`): a connection on the authored
    name, one on each address, a shared authored name surviving, an entity with no
    authored name, and the brush-entity case. Three fail against the old code, and
    disabling the ambiguity check alone fails the shared-name test.
- **The baker read `get_meshes()` as a list and threw the placement away.** Godot 4
  returns a flat two-element array from `CSGShape3D.get_meshes()` — the node's
  `Transform3D` first, then its root `Mesh`. The baker walked it as a list of
  meshes, which still found the mesh, because the second element is one, and
  silently dropped the transform, because the first element is not. A CSG node
  standing anywhere but the origin baked its visual mesh and its convex collision
  at the origin.
  - Both halves of the bake were affected: the per-entry path sets the mesh
    instance's and the collision shapes' transforms from it, and the merged path
    carries it into every surface payload.
  - There were three copies of the same misreading in `baker.gd`, so there is now
    one `_csg_mesh_pairs()` they all call. It checks the flat pair first and keeps
    the per-entry walk behind it, in either order, the way
    `HFSubtractPreview.extract_csg_meshes()` already did.
  - **Coverage** (`tests/test_baker.gd`): the flat pair keeping its transform, its
    collision hull vertices standing where the CSG node does, a bare list of meshes
    still read, nested pairs still read in either order, and nothing in giving
    nothing out. Three fail against the old code.
- **Custom brushes baked as rectangular boxes.** `append_brush_list_to_csg()`
  built every CSG stand-in with `PrefabFactory.create_prefab()`, which knows the
  primitives and falls back to a box for anything else. CUSTOM is the only shape
  that reaches that fallback, so a vertex-edited wedge, a polygon extrusion, a
  bevelled brush or a hull imported from a `.map` went into the boolean as a box
  of its bounding size and came out of the bake as one. It affected every bake
  path, because all three build their CSG through that one function.
  - A custom brush is now cut with the mesh it is drawing, which is what
    `HFSubtractPreview` already cuts with — so the preview of a cut and the bake
    of it finally agree.
  - The stand-in is placed at the mesh instance's own transform, because that is
    the space the mesh is in. Same ordering rule as before: parented first,
    positioned second.
  - A custom brush whose mesh has not been built yet still goes in as a box. That
    is wrong, but a brush that vanishes from the bake without a word is worse.
  - **Coverage** (`tests/test_bake_system.gd`): a wedge reaching the CSG as its own
    mesh and keeping its own bounds rather than the box its size field describes,
    the same wedge placed correctly under a moved and turned root, a primitive
    still taking the prefab path, and the no-mesh fallback. The first two fail
    against the old code.
- **A point entity's authored name was thrown away by every save, undo and
  duplicate.** The authored name is not the node name: it is what an I/O output
  targets and what `find_entities_by_name()` looks up. `capture_entity_info()`
  never read the `entity_name` meta and `restore_entity_from_info()` never wrote
  it, so a name survived only until the next snapshot — which is any undo, any
  redo, an autosave, a level reload, or a Ctrl+D. After that the entity answered
  to nothing and the outputs aimed at it fired into the air.
  - Every one of those paths runs through the same pair of functions, so both ends
    of the info dictionary carry the name now. Brush entities have carried theirs
    since #149; point entities were left out of that pass.
  - A prefab placed twice now gives both copies the same authored name, the same
    way two placements of a named brush entity already do. The I/O remap works off
    node names, which stay unique.
  - **Coverage** (`tests/test_entity_props.gd`): capture and restore, duplication,
    an unnamed entity gaining no metadata, and a real `LevelRoot` taken through a
    state snapshot and asked to find the entity by name afterwards. Three of the
    four fail against the old code.
- **The entity wiring overlay stayed behind when the level left the tree.**
  `HFIOVisualizer` hangs a `MeshInstance3D` and its pulse overlays off the
  `LevelRoot`, and `cleanup()` was written to take them down, but
  `LevelRoot._exit_tree()` never called it. Closing a scene or reloading the
  plugin left the mesh behind, once per reload. Every other overlay in that
  teardown was already accounted for.
  - **Coverage** (`tests/test_io_visualizer_enhanced.gd`): a real `LevelRoot`
    with the wiring drawn, taken out of the tree, asserting the mesh is gone and
    left no node behind. It fails against the old code.
- **Tilted brushes imported from `.map` as loose triangles.** A `.map` face line
  names three points on an infinite plane, not the corners of a face. Import read
  them as corners, so every brush that was not an axis-aligned box arrived as a
  handful of disconnected 3-point triangles standing wherever the file happened to
  put its plane references. A cylinder, a ramp, a wedge or a turned box from
  TrenchBroom or Hammer came in deformed and not watertight.
  - The solid is the intersection of the half spaces behind its planes, so each
    face is now worked out: a square laid on the plane, clipped by every other
    plane of the brush, and wound clockwise from outside like the rest of the
    codebase. `HFConvexClip` already had the clipping and the winding.
  - The brush's size and centre came from the same misread points and are now
    taken from the hull, which also settles the axis-aligned box path: a box
    written with plane references off in a corner used to import the wrong size.
  - **Planes that close nothing still import.** Two planes bound no solid, and a
    file can hold that. A face whose square still reaches its own rim means the
    solid is open on that side, and the old reading of the points as corners is
    the only thing left; it gives the wrong hull, but it gives one, and the brush
    is still on screen to be fixed.
  - **The whole set is retried flipped**, because the order of the three points
    settles which side is solid and editors do not agree on it. The intersection
    of the outside half spaces of a closed solid is empty, so the wrong
    orientation cannot pass by accident.
  - **Coverage** (`tests/test_map_export.gd`): a box turned on every axis written
    out with plane references 20 units clear of its own corners, asserting six
    quads whose corners land on the box and a size that matches the hull; a wedge
    coming back as two triangle ends and three quad sides; and an open plane pair
    still importing. The first three fail against the old code.
- **Cutters exported to `.map` as solid brushes, filling the holes they made.**
  A `.map` worldspawn holds additive convex solids and nothing else — the format
  has no negative brush — so every subtraction brush written into one arrives as
  matter. A doorway carved into a wall exported as a wall with a solid block
  standing in the doorway, and nothing said so until the map was opened in
  TrenchBroom or compiled.
  - `export_map_from_level()` reached into `CommittedCuts` on purpose and added
    its children to the same list as the solids, and a subtraction brush sitting
    in `DraftBrushes` went the same way. Only `PendingCuts` was filtered.
  - All three are now read as one question, `_is_cutter()`, because a cutter is
    not one state: pending, committed and frozen, or plainly subtractive. The
    operation alone misses the frozen one, which keeps whatever operation it had
    when it was stashed; the container alone misses the other two.
  - Carved shapes therefore leave uncut rather than leaving wrong. `.map` is a
    blockout exchange format, not a bake.
  - **Coverage** (`tests/test_map_export.gd`): a committed cutter, a subtraction
    brush and a pending cutter, each asserting the export carries the solid's six
    planes and only those. The first two fail against the old code.
- **Baking with the LevelRoot away from the origin put the geometry somewhere
  else.** Found by sweeping for the rest of the ordering bug below rather than
  by hitting it, and it is the worst of the family: the others were the editor
  drawing or placing in the wrong spot, this one bakes the wrong thing into what
  ships.
  - `append_brush_list_to_csg()` set each CSG stand-in's `global_transform` from
    the draft brush before adding it to the combiner. The combiner is a child of
    `LevelRoot`, so the assignment landed on the local transform and the root's
    transform was applied a second time when the shape was parented.
  - A brush at `(32, 0, 0)` with the root at `(1000, 0, 1000)` baked at
    `(1032, 0, 1000)`. A turned root was worse: the rotation doubled too, so a
    brush facing 45 degrees baked facing -135.
  - The shape is placed after `add_child()` now. All three bake paths build their
    combiner with `root.add_child()` first, so all three are covered.
  - **Coverage** (`tests/test_bake_system.gd`): a translated root and a turned
    one, asserting the stand-in's world transform matches the brush it stands
    for, position and facing. Both fail against the old code.
- **Create Radial Array could not be undone.** Ctrl+Z reached past it and undid
  whatever you did before it, while the new copies stayed in the scene.
  - `EditorUndoRedoManager.add_do_method()` takes an object, a method name and
    varargs, and GDScript cannot spread an array into varargs, so
    `HFUndoHelper.register_action()` unrolls the call by hand and stops at five
    arguments. `create_radial_array` passes six. The `match` fell through with no
    do operation registered, and `commit()` had already bailed out to a plain
    call before it got that far.
  - Past the unroll it now registers the result instead of the call: run the
    method, snapshot the state, and make that snapshot the do operation. That is
    the same kind of restore the undo side already uses, so redo has the same
    fidelity as undo, and it is the path stepping commands like rotate and nudge
    already take. No ceiling was raised, so the next six argument command is
    covered without another edit.
  - `create_radial_array` was the only command over the limit. All 43 method
    names dispatched through the commit sites were checked against their
    `LevelRoot` signatures.
  - **Coverage** (`tests/test_undo_collation.gd`): a six argument command
    registers an entry that has a do operation, and a radial array undoes and
    redoes whole. The undo test asserts the array exists before undoing it,
    because the old path never built it through `register_action()` and the test
    passed for the wrong reason at first.
    `test_transform_undo_methods_stay_within_the_helper_argument_limit` guarded
    the ceiling this removes and is gone; the rename check it shared is already
    done by `test_level_root_exposes_the_methods_undo_dispatches_by_name`.
- **Move the LevelRoot node and new brushes and restored entities landed
  somewhere else.** A `Node3D` outside the scene tree has no parent to measure
  against, so setting `global_position` or `global_transform` on it only writes
  the local one. The node then lands wherever its container puts it, shifted by
  the LevelRoot transform.
  - **Clicking to place a brush.** `place_brush()` set the position before the
    brush went into the draft or pending container. With the root at (50, 0, 50)
    a click on the origin made a brush at (50, 8, 50), and `_record_last_brush()`
    stored that same wrong point, so the grid followed the brush to the wrong
    place as well.
  - **Restoring an entity.** `restore_entity_from_info()` and
    `create_entity_from_map()` assigned the transform before parenting, so undo,
    redo, state restore, prefab placement and map import each shifted every
    entity by the root transform. Godot logged the out-of-tree transform error
    each time.
  - Each now assigns after the `add_child`. `restore_entity_from_info()` does it
    before it emits `entity_added`, so anything listening sees the entity where
    it belongs. This is the order `create_brush_from_info()` and
    `create_default_spawn()` already used.
  - **Coverage** (`tests/test_brush_system.gd`, `tests/test_entity_props.gd`): a
    click and an entity restore with the root translated away from the origin.
    All three cases fail against the old code with the exact coordinates from the
    reports.
- **You drew on a different plane from the grid you were looking at.** Having
  fixed where the overlays *draw*, the other half of the same question was
  whether the editor *acts* where it draws. It did not, and not only off the
  origin — this one is the ordinary way of working, at the world origin, with
  nothing moved.
  - The grid plane follows the last brush you made; that is what
    `record_last_brush()` is for, and the grid visibly goes there. But the ray
    that places a new brush was answered by the horizontal plane through the
    world origin regardless. Draw a brush at y=128, watch the grid rise to meet
    it, then drag out the next one — it lands back on zero, a hundred and
    twenty-eight units below the grid on screen.
  - **An axis lock was worse than wrong.** With the grid stood up on X or Z and
    the camera looking along it, a horizontal plane is parallel to the ray, so
    the raycast returned nothing at all: the drag could not start.
  - `_raycast()` now falls back to `HFGridSystem.intersect_axis_plane()` at the
    grid's own axis and origin — the plane that is actually on screen. Picking a
    brush face still wins over any plane, as it always did.
  - The old world-origin plane stays as `construction_plane_intersection()`, used
    when no grid system is loaded. That is every exported game, where the editor
    systems are never initialised, so runtime behaviour is untouched.
  - **Coverage** (`tests/test_draw_plane.gd`): the plane following the grid up
    and back down, both axis locks placing on the upright grid and a released
    lock returning to the floor, a moved root drawing on its own grid, a brush
    under the cursor still winning over the plane, and the static fallback
    keeping its old answer. Five of the nine fail against the old code.
- **The rest of the overlays drew a LevelRoot away too.** Fixing the four
  destructive previews left the same assumption everywhere else it had spread, so
  the remaining overlays were measured the same way rather than assumed innocent.
  All four were wrong:
  - **The cordon wireframe** — the box that says which part of the level a partial
    bake will take, drawn around a region other than the one it names.
  - **The entity wiring lines** — drawn between two points that are neither
    entity.
  - **The vertex and edge overlay** — the handles a vertex drag is aimed at,
    which makes the tool unusable off the origin rather than merely wrong.
  - **The prefab ghost box** — drawn around nothing.
  - Each builds its geometry from world coordinates into a node hanging off
    `LevelRoot`, so each is now pinned to world space. The previews carry a
    placement and assign it through `global_transform`; these hold world
    coordinates directly, so their instance transform is pinned to identity.
  - `tests/test_preview_placement.gd` covers every overlay in the plugin now, and
    gained an assertion that the mesh is not empty — the I/O case passed on an
    empty mesh at first, because nothing drawn has its bounds at the origin and
    the origin was close enough to pass. Four of its eleven cases fail against the
    old code.
- **Move the LevelRoot node and every destructive preview drew somewhere else.**
  Hollow, carve, clip and subtract place their overlay meshes from world-space
  measurements — a brush's own `global_transform`, a cutting plane built from
  world bounds, an intersection from `world_aabb()` — but assigned them to the
  *local* transform of a node hanging off `LevelRoot`. That is correct only while
  the root sits at the world origin with no rotation, which is the only way it had
  ever been exercised. With the root a thousand units out, the hollow preview drew
  its six walls two thousand units out.
  - The whole contract of these overlays is that you agree to an irreversible edit
    by looking at one. The clip plane is the worst of them: it is the thing being
    aimed, and it was drawn a whole root transform away from the brush it was
    about to cut.
  - The four now place through `global_transform`. `HFSubtractPreview`'s CSG
    results are the deliberate exception and stay local — `get_meshes()` reports
    them relative to a combiner that is itself parented to `LevelRoot`, so they
    were already in the right space, and the two cases now say which is which.
  - **Coverage** (`tests/test_preview_placement.gd`): the property asked of all
    six previews with the root both moved *and* turned, so a fix that only handled
    translation would not pass. Four of the seven fail against the old code.

### Added
- **A build guard against the mistake that has now been fixed six times.**
  Assigning `global_position` or `global_transform` to a `Node3D` that is not in
  the tree yet writes the local transform instead. Nothing errors, and the node
  lands shifted by its container. It stays invisible while `LevelRoot` sits at
  the world origin, which is how it usually gets exercised, so each instance was
  found by someone hitting it. The last one was found by a scan instead, in the
  baker, applying the root transform twice to geometry that ships.
  - `tools/check_placement_order.py` fails the build when a `global_*`
    assignment runs before the node is parented in the same function. It reads
    `addons/hammerforge/` and `tests/`, since a fixture with the same mistake
    builds a scene it is not describing and passes without holding the property
    it names.
  - It folds wrapped calls onto one line before matching, because gdformat
    routinely puts `add_child(` and its argument on separate lines. A deliberate
    case is marked with a `hf-allow-global-before-parent` comment rather than by
    switching the check off.
  - `--selftest` runs the detector over a known-bad and a known-good snippet and
    fails if either answer changed. CI runs it before the scan, so a detector
    that has quietly stopped detecting fails loudly rather than passing
    everything. Checked against the four historical bugs: it reports all four at
    the lines their reports named.
- **The array section draws its copies, and refuses to describe a hang.** The
  Structure section next to it learned to draw itself two waves ago; this one had
  three layouts, nine numbers between them, and a button that turned them into as
  many brushes as the numbers asked for. Nothing said how many until they existed
  — and the grid cell counts reach 32 a side, which is a lattice of over
  **thirty-two thousand brushes**: not an edit but a hang, one button press away.
  - **`HFArrayPreview`** draws the selection's own outlines at each placement the
    command would use. That is the honest picture — an array does not invent
    geometry, it repeats what you already have — and the line under the controls
    says what you are about to get: *"12 copies of 1 brush"*.
  - **One definition of where the copies go.** `HFDuplicator.CopyPlacement` and
    the three `*_placements()` builders are what `generate()`, `generate_radial()`
    and `generate_grid()` now read, and what the ghost reads. The numbers on
    screen and the brushes that appear are the same arithmetic rather than two
    copies of it that can drift.
  - **`HFDuplicator.can_generate()` caps an array at 256 brushes** — the same
    budget, in the same currency, that `HFDomeBuilder` already keeps. The refusal
    names the number asked for, because "too many" without a number leaves you
    guessing which control to turn back. Asked before an undo action is opened and
    before a ghost is drawn.
  - **The ghost waits to be asked for.** The structure ghost can appear when its
    section is opened, because opening that section is the request. These controls
    share an always-open section with a dozen other tools, so a ghost of three
    offset copies would follow every brush you clicked. Turning an array control
    is the request instead; creating the array, clearing the selection or leaving
    the Build tab puts it away.
  - **Coverage** (`tests/test_array_preview.gd`): each layout's placements
    measured, including a lattice leaving out the cell its source occupies and a
    radial rise climbing; the budget in copies and in total brushes, and its
    refusal naming the number; the ghost drawn, redrawn, and cleared on every gate
    that should clear it; a thirty-two-cube grid drawing nothing *and* building
    nothing; the ghost and the button agreeing on the count; and the ghost not
    appearing until it is asked for.

- **A structure built on a selection now faces the way that selection faces.**
  Create placed a structure at the selection's pivot and then built it square, so
  selecting a wall standing at forty-five degrees and building an arch on it gave
  an arch standing square in a room that was not. The position half of "centred on
  the selection" was there from the start; the facing half was the sentence's
  missing clause, and every piece of plumbing it needed — a rotated placement that
  builds, serializes, previews and relocates correctly — was finished by the two
  waves before this one.
  - `HFTransformSystem.resolve_selection_basis()` is the companion to
    `resolve_pivot()`, and `HFDockBrushHandler.create_placement()` is now the one
    definition of where a new structure lands. The ghost reads the same function,
    so the angle is visible before the button is pressed rather than discovered by
    pressing it.
  - **A selection has to agree with itself.** Two brushes turned different ways
    give the world axes, because there is no single direction to inherit and
    guessing one is worse than not answering.
  - **A basis that is not a pure rotation gives the world axes too.** A mirrored
    or scaled brush has axes that are not a facing, and building a structure
    through a negative-determinant basis would invert the winding of every face in
    it. `HFTransformSystem.is_rotation_basis()` is now the single definition of
    that test, replacing the copy the generator system had been keeping.
  - **Coverage** (`tests/test_selection_basis.gd`,
    `tests/test_structure_dock_commands.gd`, `tests/test_structure_preview.gd`):
    the predicate against turns, mirrors, squashes and uniform scales; a selection
    agreeing, disagreeing, spoiled by one mirrored member, mixing a brush with an
    entity, and naming a brush that is gone; a structure built on a turned brush
    coming out turned, keeping positive determinant on every piece, and not
    reading as edited afterwards; and the ghost leaning the same way first.

### Fixed
- **One nudged brush no longer throws a structure back across the level.**
  Relocation asked for unanimity, which sounds like the stricter test and was in
  fact the worse one. Drag a twelve-piece arch five hundred units, nudge a single
  brush by one, and all eleven pieces that agreed were overruled: the section
  reported *twelve* pieces edited by hand rather than one, and the next Update
  carried the whole arch back to the origin it was created at.
  - **Where a structure went is decided by vote.** Pieces are grouped by the
    rigid transform they received, and a group holding more than half of them is
    the relocation. The pieces outside that majority are the hand edits, which is
    what they always were. A tie decides nothing, which is the right answer for a
    structure that has been pulled in two.
  - **A non-rigid move never joins a group**, so a mirrored or squashed structure
    cannot out-vote its own refusal however many pieces agree on it.
  - **A structure nobody can locate says so.** When no majority exists and the
    pieces have plainly moved, the section reads *"These pieces no longer agree
    on where the structure is. Update will rebuild it where it was created —
    Detach to keep them where they are."* Where a rebuild lands is the larger
    surprise, and a count of edited shapes never mentioned it. This also gives a
    mirrored structure a reason of its own instead of a misleading hand-edit
    count.
  - **Coverage** (`tests/test_generator_system.gd`,
    `tests/test_structure_preview.gd`): eleven of twelve agreeing carrying the
    structure and the twelfth counted as the single edit; the rebuild staying put
    around that stray piece; a bare majority accepted and a two-two tie refused; a
    mirror out-numbering itself and still refused; a structure down to its last
    piece still able to say where it is; and the section's message checked for
    naming the placement before the shapes.

### Added
- **A structure you have turned rebuilds turned.** Relocation understood
  translation and nothing else, so a flight of stairs rotated into the corner it
  belongs in and then given two more steps squared itself back up on the world
  axes — and, because every piece was standing in a basis it had not been
  recorded in, first told you all of them had been edited by hand. Both halves of
  that were the same missing fact.
  - Each piece now records **how it was turned** as well as where it was put, and
    the question asked of the pieces is a rigid transform rather than a vector: if
    every surviving piece received the same turn and slide, the structure was
    moved as a whole and the placement is composed with it.
  - **A move that is not rigid answers no.** A squash is not a relocation, and a
    mirror is refused outright — rebuilding a structure through a
    negative-determinant basis inverts the winding of every face in it and does
    not look wrong until the bake. Both leave the placement alone and let the
    pieces read as edited, which is what they are.
  - **A piece is asked about its shape in the basis it was recorded in**, not the
    one it is standing in. That is what separates a structure turned as a whole
    from a piece reshaped by hand, and comparing the same recorded `Basis` on both
    sides is exact where un-turning the current one would compare the rounding of
    one arithmetic path against the rounding of another.
  - **Levels saved before this open unchanged.** A signature with no basis is
    answered with the placement's own, which is what every piece the generator
    built was given — so an older structure recovers a turn with no migration and
    no re-record.
  - The structure ghost follows: select a piece of a turned structure and the
    preview of the rebuild stands over it at the angle it actually has.
  - **Coverage** (`tests/test_generator_system.gd`,
    `tests/test_live_generators_integration.gd`,
    `tests/test_structure_preview.gd`): a turn recovered and rebuilt in place; a
    turn and a slide together; pieces turned one at a time still reading as edits;
    a mirror and a squash both refused; a turn surviving the save format; a record
    with its piece bases stripped still recovering one; and every rebuilt piece
    checked for positive determinant.
- **The Structure section draws what it would build, before it builds it.** Every
  other way of making geometry in HammerForge shows you the shape while you are
  still choosing it: a drag has its box, a hollow has its walls, a clip has its
  cut. A structure had eight numbers and a button. You pressed the button to find
  out what "sweep 60, rings 6" meant, and if it was wrong you undid it and pressed
  it again.
  - **Now the numbers draw.** `HFStructurePreview` stands a pale wireframe where
    Create would put the structure and follows every control as you turn it — a
    dome gains a ring, a spiral gains a step, an arch widens. One line mesh for
    the whole structure rather than one node per piece, because a dome is a few
    hundred pieces and a redraw happens on every keystroke.
  - **For a structure that already exists it stands over the real pieces**, at
    the placement a rebuild would use — the recorded placement plus the
    relocation delta, so a structure you dragged into a doorway previews in the
    doorway. That is the moment that matters: you can see the arch getting wider
    before you agree to rebuild it.
  - **A combination that cannot be built draws nothing and says why.** An empty
    viewport is not an answer, so the refusal goes in the section's own message
    line, beside the other things worth knowing before pressing the button. You
    find out while you are still choosing rather than afterwards.
  - **The ghost belongs to the section.** It appears while Structure is open and
    the Build tab is in front, goes when either stops being true, and clears once
    Create or Update has happened — the real thing is there, so it stops standing
    on top of itself. It records nothing, is never written to a `.hflevel`, and is
    destroyed with its `LevelRoot`.
  - A redraw also takes down the "these settings would drop painted faces"
    warning, so the second press of Update that goes ahead has to be earned
    again. An acknowledgement that outlives the sentence asking for it is not one.
  - **Coverage** (`tests/test_structure_preview.gd`): the ghost measured against
    the piece count for each type, stood at the placement it claims, followed to
    a structure that was moved, cleared on every gate that should clear it, drawn
    again after a plugin-reload teardown, and checked for leaving no node behind
    in the level.
- **A structure library, and one place to add to it.** The live-generator wave
  built a type table and put one thing in it. Two problems sat behind that single
  entry, and only one of them was "we need more generators": the dock could not
  afford a second one. Its Arch section was six named SpinBox members, six
  hand-built rows, a loader listing the six by name and a reader listing them
  again — four of everything, per generator. The cost of adding a generator was
  never the arithmetic; it was the dock.
  - **Builders describe their own settings.** `HFGeneratorSchema` is the shape of
    that description — key, label, type, range, default, tooltip — and the dock
    builds its controls from it. One **Structure** section with a type dropdown
    now serves every generator, and adding another needs no dock code at all.
  - **Stairs** (`HFStairsBuilder`) — a straight flight, one brush per step, solid
    underneath or floating treads. After the box it is the most common piece of
    built geometry in a level, and building one by hand is a dozen brushes each
    offset from the last in two axes at once, every offset a chance to be a unit
    out.
  - **Spiral stairs** (`HFSpiralStairsBuilder`) — a flight that turns as it
    climbs, with an optional newel post. Every tread is computed as the annular
    wedge a tread at that radius actually is. The old answer was a radial array
    with a rise, which repeats a shape around an axis but cannot compute the shape
    — the same limitation that made the arch worth building.
  - **Dome** (`HFDomeBuilder`) — a hemisphere in rings, one brush per panel, with
    an adjustable sweep for an open crown and a wall that can go all the way to
    solid. Built in rings rather than in patches of sphere because four points on
    a sphere at two latitudes and two longitudes are *not coplanar*, and a brush
    is a convex solid with planar faces. The frustum band of a cone is planar, so
    rings give a real brush where patches give a warped quad.
  - **`HFConvexClip.solid_from_rings()`** builds a solid from the corner rings of
    its faces, collapsing coincident corners. That is what lets a generator write
    the general eight-corner case once and still get a wedge where the shape
    pinches — a dome panel at the crown, a spiral tread meeting the axis.
- **A structure you have moved rebuilds where it now is.** Regeneration used to
  build at the placement recorded when the structure was created, so dragging an
  arch into a doorway and then widening it put the arch back at the origin. Each
  piece now records where it was put; if every surviving piece has moved by the
  same amount the structure was relocated, and it rebuilds there. Pieces that
  disagree were moved individually, which is editing rather than relocating, and
  the placement stays.
- **The Structure section says how many pieces a rebuild would overwrite.** Each
  piece also records a hash of what it *is*, so a vertex drag, clip, bevel, resize
  or turn is visible: *"3 pieces have been edited by hand. Update will rebuild
  over them — Detach to keep them."* Detach was always the answer and always sat
  beside Update, but a choice you do not know you are making is not a choice.
- **Structure library coverage** (`tests/test_stairs_builder.gd`,
  `tests/test_spiral_stairs_builder.gd`, `tests/test_dome_builder.gd`,
  `tests/test_generator_schema.gd`, and additions across the generator, convex-clip
  and integration suites): every panel of every structure measured for planarity,
  closure, convexity and outward winding; each refusal fired on its own boundary
  and not one step inside it; every type baked against an untouched control; and a
  saved-and-reopened level checked for *not* claiming its pieces were edited.

### Fixed
- **An entity property containing a quote came back truncated, silently.**
  `_parse_key_value()` found four quote positions and sliced between them, which
  is right until the value has a quote of its own — `"message" "he said "hi""`
  read back as `he said `, with no error, because four quotes is exactly what a
  valid line has. Key and value are read as quoted tokens now, honouring `\"`
  and `\\`, and written through `MapIO.escape_property()`. Unescaping is
  deliberately conservative: a backslash before anything else is left alone, so
  an unescaped Windows path from another tool still reads as written. The same
  root cause cost a value its `//` — the comment stripper cut the line at the
  first one it found, so a URL in a property left an odd number of quotes and no
  way to parse. It respects quoting now. The `.map` format defines no escaping
  rule of its own, so the contract here is HammerForge's: what it writes, it
  reads back unchanged.
- **Clip to Face Plane could not be undone, and could not be reached.** Two
  separate faults in one command, and the second hid the first. It looped over the
  targets calling `clip_brush_to_face_plane()` directly and then recorded a
  *history label* — a line in the history browser, not an `EditorUndoRedoManager`
  action. An advertised destructive command replaced several authored brushes with
  no way back. The batch now commits through `HFUndoHelper` as one action against a
  new `clip_brushes_by_plane()`, and the cut is carried as a `Plane` rather than a
  brush id and a face index, so a redo still works when the reference brush was
  itself one of the targets. Meanwhile the documented workflow could not be
  performed at all: entering Face Select saves the object selection and then clears
  it, so by the time a reference face existed there was nothing left to cut. The
  command reads that saved selection now, and releases both selections afterwards
  rather than restoring brushes the cut has just replaced. `Alt+Shift+X` was in the
  keymap and in the guide, but the viewport router never dispatched it, so the flow
  in the guide could not be followed from the viewport either.
- **Reset Rotation erased scale set with Godot's own gizmo.** `axis_permutation()`
  normalises the basis columns, so a purely *scaled* box read as an axis permutation
  and had its scale wiped along with a rotation it did not have. A basis is rotation
  times scale; the cleared basis is now that scale on its own, read back with
  `get_scale()`. A brush that is only scaled has nothing to clear and is left alone.
  The quarter-turn fold into `size` carries the scale with it, because scale belongs
  to the local axis the fold is moving.
- **Flip left per-face appearance on the side it started.** When a local mirror maps
  a primitive onto itself the geometry needs no surgery, so the faces were left
  alone — but face data is held by index, and the mirror sends each face to where a
  *different* face used to be. A material on the positive X face stayed on positive
  X after an X flip. Each face now takes the data of the face its own reflection
  lands on, mirrored back into place, so material, UVs and paint travel with the
  geometry and the brush keeps its shape and its resize handles.
- **A collated run of edits redid only its last step.** Godot's `MERGE_ENDS` keeps
  the first action's undo operations and the last action's do operations, which is
  correct only when that last do names an absolute final value. Rotate and nudge
  register a *step*, so three quick presses undid forty-five degrees and redid
  fifteen — the history claimed one action and performed a different one.
  `HFUndoHelper.commit()` takes an `absolute_redo` flag for stepping commands: it
  runs the method itself, captures the result, and registers a snapshot as the do
  operation, committing without executing so the work is not done twice. The
  collation tags were also global, so a run could merge a changed selection, a
  reversed direction, a different axis or a different brush. They now name the
  command, the targets, and the inputs that change what the press means.
- **Rejected Structure settings reported success.** Every field can be in range
  while the combination is not — a wall as thick as the arch is wide, an arc of
  zero, a wide arc across too few segments. The builder refused those and created
  nothing, but the dock committed an undo action anyway and said *Created* either
  way. `HFGeneratorSystem.can_build()` answers whether settings would build without
  building anything that lasts, and the dock asks before it opens an action. A
  refused Create says why; a refused Update says the structure was not changed and
  leaves it standing. Both paths read the level back afterwards rather than
  assuming. `Ctrl+Shift+A` is advertised for Create Structure but the viewport
  router never dispatched it either; it does now, guarded on the level and the dock
  rather than on a selection count, because with nothing selected it builds at the
  origin.
- **Updating a structure silently dropped painted faces.** Regeneration said it
  preserved materials, but it read and reapplied only `material_override`. The Paint
  tab writes `FaceData.material_idx`, per-face UV settings and paint layers, and
  none of it came back — so painting a generated arch and then nudging its radius
  reset the work, with no warning, because the edited-piece hash ignores appearance
  entirely. The whole per-face appearance is now captured and put back. Where a
  rebuild cannot line the pieces up, `appearance_at_risk()` names the painted pieces
  that would be dropped, and the section warns and waits for a second press, with
  Detach beside it as it always was.
- **Whole-level replacement kept the records of the geometry it replaced.**
  `clear_brushes()` never touched the generator system, so a `.map` import or an
  example load left the records for the discarded level in memory — and those
  orphans went into every undo snapshot and every `.hflevel` save afterwards. It
  clears them with the brushes now. Restoring a state puts the right records back,
  so undo is unaffected, and deleting a single generated piece still leaves its
  record alone, because that record is what warns about the gap and rebuilds it.
- **Open stairs sat above the point they were placed on.** Both open stair builders
  centred against the *nominal climb*. An open flight starts at the underside of its
  first tread, so it spans `rise - tread_thickness` less than the climb and landed
  half that high — four units on the defaults. Both now derive the vertical shift
  from the lowest and highest Y they actually emit. The spiral counts its centre
  post when it has one, which leaves that case exactly where it was and also fixes
  one nobody had noticed: a tread thicker than the rise reaches below the foot of
  the post, and was off centre the other way.
- **Carve could not find a rotated brush where it actually reached.** The broad
  phase built each candidate's box from `global_position` and `size`, which describe
  a brush *before* it was turned. A long brush yawed 45 degrees reaches well outside
  that box, so a carver sitting on its far end was rejected with "no overlapping
  brushes found" and the cut silently did not happen. It reads `world_bounds_of()`
  now — the same bounds the narrow phase two lines later already used.
- **Texture lock ignored UV rotation when a brush moved.**
  `adjust_uvs_for_transform()` rotates the projected move by `uv_rotation` before
  scaling and subtracting it, matching the carve system's math, so a texture on a
  rotated face stays pinned in world space instead of drifting along the wrong axes.

- **Two test files, 121 tests, had been silently skipped for two waves.**
  `tests/test_transform_integration.gd` and `tests/test_transform_system.gd` called
  `HFBrushSystem._check_axis_aligned_box()`, which the generators wave deleted when
  hollow stopped needing it. GDScript resolves that at parse time, so both files
  failed to load — and GUT skips a file it cannot load with a warning rather than a
  failure, leaving the totals slightly smaller and entirely plausible. The tests
  are rewritten against what replaced the guard (nothing refuses a rotated brush
  any more), and `tests/test_suite_integrity.gd` now fails the suite when any test
  file will not load, so a silent skip cannot happen again.

### Documentation
- **Three places still said Hollow refuses a rotated brush.** It stopped refusing
  when it moved to shelling a brush against its own face planes, and the guide
  already described the current behaviour correctly under **Hollow** itself — so it
  was contradicting itself two sections apart, and sending the reader to Reset
  Rotation as the way back from a problem that no longer exists. Corrected in the
  cutting-section callout, in **After you rotate**, and in the doc comment on
  `reset_rotation_selected()`.
- **The Clip to Face Plane walkthrough described an order that cannot work.** It
  said to enter Face Select, pick the face, *then* select the brushes to cut — but
  selecting an object closes Face Select and clears the face. The guide now says to
  select the targets first, and explains why the order is what it is.
- Reset Rotation is no longer described as the way back to Hollow, Clip and Carve.
  The structure walkthrough now covers per-face paint surviving a rebuild, and the
  warning when it cannot. Test and script counts refreshed.

### Changed
- The dock's **Arch** section is now the **Structure** section, with a type
  dropdown. `Ctrl+Shift+A` keeps its action id, so existing custom keymaps still
  resolve, and builds whatever type the section is showing.
- **Live generators — structures you can go back and change.** A generator turns a
  handful of numbers into a lot of brushes, and until now the numbers were gone
  the moment the brushes existed. An arch became eight loose brushes with no
  memory of the radius, thickness or segment count behind them, so wanting a
  slightly wider one meant deleting everything and building it again — losing any
  materials painted on the old one. Radius and segment count are exactly the
  values a designer tunes by looking at the result.
  - **`HFGeneratorSystem`** keeps a record of what each generator made: its type,
    its settings, where it was placed, and the brushes it produced. Shaped after
    `HFDuplicator`, which already remembers its sources and instances, and
    persisted the same way — the records ride in the state snapshot, so they
    travel through undo and into the `.hflevel` file.
  - **The Arch section becomes an editor.** Select any piece of an arch and the
    section loads that arch's settings, the button reads **Update Arch**, and a
    **Detach** button appears. Change a number and the structure rebuilds in
    place.
  - **Materials survive a rebuild.** Each piece's material is captured in order
    and reapplied by index, so nudging a radius does not cost a texture pass.
    When the segment count changes the shorter list wins and the extra pieces take
    the default, since there is no correspondence to preserve.
  - **Detach** forgets the record and leaves ordinary brushes — the way out for a
    structure that has been edited by hand and should stop being rebuilt out from
    under those edits. It sits beside Update so the choice is visible rather than
    discovered afterwards.
  - Validation runs before anything is deleted, so an unbuildable change refuses
    and leaves the structure standing rather than removing it and then failing to
    replace it.
- **Live generator coverage** (`tests/test_generator_system.gd`,
  `tests/test_live_generators_integration.gd`,
  `tests/test_live_generator_commands.gd`, 63 cases): records surviving undo and
  the save format, material preservation across a changing segment count, stale
  records staying harmless, regenerated geometry still baking outward against an
  untouched control, and the ordering contracts that keep a bad edit from
  destroying what it cannot rebuild.

### Changed
- **A generator record is a hint, never ownership.** Brush ids are reissued as the
  id counter moves, so a stale entry in one record could name a brush that now
  belongs to something else — and a rebuild would quietly delete a neighbour's
  geometry. Deletion checks each brush's own `hf_generator_id` before removing it.
- **Generators — one description, many brushes.** Three gaps that looked unrelated
  turned out to be the same shape of problem.
  - **Hollow works on any convex brush, at any rotation.** It was the last
    operation that rebuilt what it touched as axis-aligned slabs, and so the last
    reason `_check_axis_aligned_box()` existed. It needed no new algorithm: the
    inside of a hollow brush is the same solid with every face pushed inward by
    the wall thickness, so shelling is the progressive remainder carve already
    runs, with the brush supplying its own planes. One face gives one wall — which
    means hollowing a cylinder now gives you a pipe.
  - **A parametric arch.** `HFArchBuilder` turns radius, wall thickness, depth,
    arc degrees, segment count and start angle into one brush per voussoir. The
    radial array can repeat a shape; it cannot compute the wedge an arch is made
    of. Reachable from a section in the Build tab, the command palette, and
    Ctrl+Shift+A, and placed on the selection or the world origin.
  - **Radial arrays can climb.** A `rise` per copy turns the ring into a helix,
    and with a box as the source, a spiral staircase. Zero keeps the flat ring
    exactly as it was, and a duplicator saved before the field existed loads as
    zero.
  - Hollow's confirmation now names the number of walls it is about to make, and
    its preview outlines the real walls instead of six axis-aligned slabs. The
    validation is exact for any shape too: if the inset planes cross, there is no
    interior, where the old rule compared twice the thickness against the smallest
    dimension and only ever meant anything for a box.
- **Generator coverage** (`tests/test_arch_builder.gd`,
  `tests/test_generators_integration.gd`, plus rewritten hollow suites, 55 cases):
  closure, convexity, neighbouring segments sharing a whole face, arch dimensions,
  helix rise, and bake-level winding proofs each paired with an untouched control.

### Fixed
- **Shelling a brush trusted each face's own normal, and a primitive mesh has
  faces whose normal cannot be trusted.** A sphere's poles carry near-degenerate
  triangles whose cross product is long enough to pass any sane epsilon but points
  in a direction that is numerical noise. One of those flipped turns an inset
  plane inside out, and hollowing a sphere reported that there was no room inside
  it. Plane orientation is now measured against an interior point rather than
  taken from the face, which is a question with an answer.

### Changed
- **Hollow and carve refuse brushes with more than 128 distinct planes.** Every
  plane is a split of a growing face set, so cost and piece count climb together.
  A box has six and a cylinder sixty-six, both fine; a sphere has thousands,
  because every triangle is its own plane. Hollowing one measured sixty seconds
  and 2,051 brushes. Both operations now check first and refuse with the real
  number rather than grinding the editor to a halt.
- **Precision cutting — clip and carve along any plane.** Clip could only split a
  brush along X, Y or Z, and both clip and carve rebuilt what they touched as
  axis-aligned boxes, so both refused a cylinder, a polygon-tool brush, a merged
  brush — and, once the free-transform work above shipped, any brush the user had
  rotated. Three of the tools a level designer reaches for most were refusing to
  touch the results of a brand new feature.
  - **`HFConvexClip`** (`hf_convex_clip.gd`) splits a convex solid along an
    arbitrary plane and is now the geometry behind both operations. It takes faces
    and a `Plane` and returns faces, with no reference to the scene, so both
    callers and their tests work without a level.
  - **Clip** takes any plane, on any convex brush, at any rotation. The plane is
    taken into the brush's own frame, so both pieces inherit the original
    transform and rotation is carried rather than handled. A piece that is still
    an axis-aligned box in that frame is emitted as a `BOX` and keeps its resize
    handles, so the commonest cut of all behaves exactly as it did.
  - **Clip to Face Plane** (Alt+Shift+X) cuts along the plane of a selected face.
    With rotation available this is the cheapest route to an angled wall or a
    chamfered corner without typing coordinates.
  - **Carve** runs progressive remainder over the carver's own face planes rather
    than the six sides of its bounding box, which is the same algorithm it always
    used, generalised. A rotated carver, a cylinder, or a merged brush all cut now.
  - **Both previews show the real cut.** The clip and carve previews drew scaled
    unit boxes, which is a lie for every angled cut; they now run the same split
    the tools run and outline the actual resulting pieces.
  - The axis-aligned guard is down to Hollow alone, which insets every face inward
    off `size` and is a different algorithm.
- **Cutting coverage** (`tests/test_convex_clip.gd`, `tests/test_carve_tool.gd`,
  `tests/test_cutting_integration.gd`, `tests/test_cutting_commands.gd`, 96 cases —
  carve had no dedicated suite at all before this): volume conservation, closure
  (every edge shared by exactly two faces), bake-level winding proofs each paired
  with an untouched control, planes that graze a face or pass through a vertex,
  repeated cuts, coincident carver and target planes, distant origins, and scaled
  brushes.

### Fixed
- **Clip to Convex produced entirely inside-out geometry.** `_faces_from_convex_hull()`
  ordered each rebuilt face counter-clockwise about its outward normal, and
  HammerForge reads faces clockwise from outside, so every brush repaired by Clip
  to Convex baked inverted — invisible in the viewport, obvious in a bake. Found by
  turning this wave's winding check on the one other place in the codebase that
  orders a ring of coplanar vertices. The duplicate ring sorter is deleted; both
  callers now go through `HFConvexClip.sort_coplanar_cw()`, whose name states the
  convention.
- **Free transform — rotate, flip and array.** HammerForge could not turn a
  brush. Every brush was authored axis-aligned, so a diagonal wall or an angled
  ramp was unreachable except by hand-placing faces with the polygon or path
  tool. The plumbing had been there all along — the baker, the snap system, the
  gizmos and the `.hflevel` writer all already carried a full `Transform3D`, and
  `FaceData.adjust_uvs_for_rotation()` had been written for this and never
  called. What was missing was the authoring layer.
  - **Rotate** (R / Shift+R) turns the selection by a configurable step, about
    the locked axis or Y, around the selection's median point, the world origin,
    or the active object. With Texture Lock on, the texture stays pinned in world
    space, which is what the setting already means for moving and resizing.
  - **Flip** (Shift+M) mirrors the selection across the locked axis, or X.
    A mirror has determinant -1, which would invert triangle winding and bake
    every face inside out; instead the reflection is folded back through a
    reflection along one *local* axis, so the basis stays right-handed and every
    world vertex lands exactly where the mirror puts it. A shape a mirror maps
    onto itself, like a box, keeps its primitive and its resize handles; one it
    does not, like a wedge, has the mirror baked into its faces.
  - **Reset Rotation** (Alt+R) clears a rotation and keeps the position. Hollow
    reads world extents straight off `size` and refuses a rotated brush, so this
    is the way back to it. A quarter turn is folded into the brush size rather
    than snapped away, so clearing it never moves geometry. (Clip and Carve
    refused rotated brushes for the same reason until the precision-cutting work
    below taught them to split real geometry.)
  - **Array layouts**: the Duplicate Array section gains **Radial** (copies
    around an axis, with a "Fill 360°" helper) and **Grid** (a 3D lattice)
    beside the existing linear run. Radial copies compose their transform through
    the same rotation code, so there is one implementation, not two.
  - Reachable from the viewport hotkeys, the floating context toolbar, the Space
    context menu, the command palette, and a Transform section in the dock's
    Selection Tools. New subsystem `systems/hf_transform_system.gd`; new
    `rotate_snap_degrees` and `transform_pivot_mode` settings, saved with the level
    beside `texture_lock`.
- **Free-transform coverage** (`tests/test_transform_system.gd`,
  `tests/test_transform_array.gd`, `tests/test_transform_integration.gd`,
  `tests/test_transform_commands.gd`, 129 cases): the rotation and mirror algebra,
  four quarter turns returning home, double flips being exactly the identity, and
  — the ones that matter — bake-level winding proofs that mirrored geometry still
  faces outward, each paired with an untouched control so a failure cannot be
  confused with a broken measurement.
- **The HammerForge Console** — a dashboard on its own main screen, opened from
  the switcher at the top of the editor beside 2D, 3D and Script, and the
  addon's front door. Three tabs: **Status**, a red / amber / green board of eight checks
  (level root, geometry budget, bake freshness, level check, material palette,
  player spawn, autosave, session log) where each lamp is accompanied by what was
  measured, the threshold it is measured against, and the one button that
  resolves it; **Controls**, every HammerForge switch on one screen grouped into
  Viewport / Bake / Safety net, captioned and searchable by description as well
  as by name; and **Log**, HammerForge's own messages lifted out of Godot's
  shared Output panel, with the level counts doubling as the filter.
  New modules: `hf_console_log.gd`, `hf_status_board.gd`, `plugin_console.gd`,
  and `ui/hf_console_panel.gd`, `ui/hf_console_controls.gd`,
  `ui/hf_console_log_view.gd`, `ui/hf_status_row.gd`, `ui/hf_status_lamp.gd`.
- **Console coverage** (`tests/test_console_log.gd`, `tests/test_status_board.gd`,
  `tests/test_console_panel.gd`, 64 cases): every severity threshold, the log
  buffer's cap / repeat collapsing / BBCode escaping / re-entrancy guard, and two
  drift guards asserting that every switch on the Controls tab still addresses a
  property `dock.gd` and `level_root.gd` actually declare.
- **Console preview harness** (`tools/hf_console_preview.gd`): renders the three
  tabs to PNGs so a layout change can be judged without opening the editor.

- **A status lamp in the 3D viewport toolbar** (`ui/hf_status_strip.gd`): the
  Console's overall severity and one-line summary, beside the work rather than
  on the screen you switched away from, and a click away from the board that
  explains it. It reads the Console's own evaluation, so the two cannot disagree.

### Fixed
- **Every entity I/O connection on a brush was silently deleted by saving,
  autosaving, undoing, or duplicating it.** `get_brush_info_from_node()`
  captured `visgroups`, `group_id` and `brush_entity_class` but not
  `entity_io_outputs` or `entity_name`, and `create_brush_from_info()` could not
  restore what was never captured. Everything that round trips a brush goes
  through those two functions, so a trigger kept its class and lost its wiring.
  Both fields are captured and restored now, and outputs are deep copied so a
  restored or duplicated brush does not share dictionaries with its source
  ([#149](https://github.com/saworbit/hammerforge/issues/149)).
- **Baking renamed every trigger and detail brush, which broke the runtime I/O
  it was wired into.** `_append_trigger_volume()` and `_append_detail_mesh()`
  named their output `Trigger_0` and `FuncDetail_0` and set no `entity_name`, so
  a connection aimed at `door_sensor` had nothing to find and the dispatcher
  dropped the event. The baked node takes the authored name and carries it as
  `entity_name`. A brush still sitting on a Godot generated name keeps the
  indexed fallback rather than handing every unnamed trigger the same alias
  ([#140](https://github.com/saworbit/hammerforge/issues/140)).
- **Every baked `func_detail` collision body sat at the world origin.**
  `_append_detail_mesh()` never assigned `body.transform`, so the `StaticBody3D`
  stayed at (0, 0, 0) with only its child shape placed at the brush. Anything
  reading `collider.global_position` got the origin, and rotating the body at
  runtime swung the shape across the scene. The body takes the mesh transform;
  the shape lands in the same world position it always did
  ([#158](https://github.com/saworbit/hammerforge/issues/158)).
- **`HFIORuntime.fire()` silently dropped events fired by an entity's authored
  name.** Delivery resolved `entity_name`, but the reverse lookup that finds a
  source indexed `node.name` only, so firing `secret_button` on a node Godot had
  named `Area3D_Baked_1` found nothing. Sources are indexed under both names,
  and firing by either dispatches exactly once
  ([#151](https://github.com/saworbit/hammerforge/issues/151)).
- **A batched operation told listeners that deleted brushes were selected, and
  never told them the brushes were gone.** `_flush_batched_signals()` filtered
  `brush_added`, `brush_removed` and `brush_changed` out of the queue, harvested
  their ids, and emitted `selection_changed` with them instead. Caches and
  spatial trees never heard about removals while the dock was handed a list of
  dead ids. The flush emits the queued signals in order now, dropping only exact
  repeats. `selection_changed` is emitted by nothing: `LevelRoot` holds no brush
  selection to report, Godot's `EditorSelection` does. Its one consumer was the
  dock resyncing its surface panel, so `delete_brush()` emits
  `face_selection_changed` when it actually clears a selected face, which
  batching collapses to one emission per delete
  ([#139](https://github.com/saworbit/hammerforge/issues/139)).
- **`entity_added` and `entity_removed` were declared on `LevelRoot` and emitted
  nowhere.** The spec and the MVP guide both promise them to docks and
  integrations, and a search of the tree found the two `signal` lines and
  nothing else. They fire now from the four places entities enter and leave a
  level: `add_entity()`, `restore_entity_from_info()`,
  `delete_entities_by_paths()` and `clear_entities()`, routed through the
  batcher. `entity_removed` fires while the node is still in the tree, so a
  listener has something valid to clean up against
  ([#150](https://github.com/saworbit/hammerforge/issues/150)).
- **Every custom, beveled, carved, polygon and prism brush exported to `.map`
  came out inside out.** `FaceData` winds clockwise seen from outside, and a
  `.map` plane is read as `(b - a) x (c - a)`, which is the opposite order.
  `_faces_to_map_lines()` wrote the vertices straight through, so a Right face
  that should have written `(1, 0, 0)` wrote `(-1, 0, 0)` and compilers rejected
  the brush. The box path had always agreed with the format; the face path does
  now. The same conversion was missing on import, so a correct `.map` file from
  another editor was read inside out too, and it is applied in reverse there
  ([#148](https://github.com/saworbit/hammerforge/issues/148)).
- **Importing a file that was not a map cleared the level and said it worked.**
  `parse_map_text()` returned `{"entities": [], "brushes": []}` for any text at
  all, `import_map()` only rejected a completely empty dictionary, and the dock
  ignored the return value and printed `Imported .map` regardless. The parser
  reports unbalanced braces, braces with nothing open, face lines that are not
  three points, key/value lines that are not, text outside any block, and
  brushes that produce no geometry. `import_map()` refuses before it clears
  anything, and the dock validates the file before it opens an undo action, so a
  bad import leaves nothing to step back over
  ([#174](https://github.com/saworbit/hammerforge/issues/174)).
- **Ticking Generate LODs killed the bake.** `_postprocess_mesh()` called
  `generate_lods()` on an `ArrayMesh`, which has no such method in Godot 4; it
  lives on `ImporterMesh`. Every bake with the option on stopped at
  `Invalid call. Nonexistent function 'generate_lods' in base 'ArrayMesh'`. The
  mesh round trips through `ImporterMesh.from_mesh()` and `get_mesh()` with
  Godot's own import angles, keeping surface materials. An empty mesh or a
  failed conversion returns the original with a warning instead of aborting
  ([#138](https://github.com/saworbit/hammerforge/issues/138)).
- **The material atlas asked for mipmapped filtering and never built any
  mipmaps.** The atlas material sets `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` and
  the tiles carry a 2px gutter for the express purpose of stopping bleed across
  mip levels, but `Image.create()` was called with mipmaps off and
  `generate_mipmaps()` was never called, so the sampler had exactly one level
  and distant surfaces shimmered. The albedo atlas and every PBR channel atlas
  generate them now, and a refusal is logged rather than leaving the sampler
  with nothing ([#157](https://github.com/saworbit/hammerforge/issues/157)).
- **Two saves to the same file could finish in the wrong order and leave the
  older one on disk.** `start_hflevel_thread()` collected a finished worker and
  then started the incoming job immediately, jumping over anything already
  queued behind that worker. With save B pending and save C arriving, the order
  ran A, C, B. A collected worker hands its slot to the oldest queued job and
  the new one goes to the back. Draining also skips a job it cannot start, so a
  discarded entry no longer strands the writes behind it
  ([#51](https://github.com/saworbit/hammerforge/issues/51)).
- **Painting across a large level threw away work before you saved it.**
  `_unload_region()` removed every chunk in a streamed out region and never
  wrote them; `_save_region_file()` only ran during an `.hflevel` save. Moving
  the cursor into the next region discarded the one behind it, and coming back
  loaded either nothing or an older sidecar. A region is written before its
  chunks are dropped, and a failed write keeps it loaded and says so once rather
  than every frame ([#172](https://github.com/saworbit/hammerforge/issues/172)).
- **A level save reported success while its region files were missing.**
  `_save_region_file()` ignored the result of `save_to_path()` and marked the
  region as having data either way, and `save_loaded_regions()` returned
  nothing, so the main write went ahead and the dock said the save worked. Both
  report now, a region is only recorded once its file exists, and
  `save_hflevel()` stops before the level write instead of shipping an index
  pointing at absent sidecars. The failure is reported as an autosave or a
  manual save to match what it actually was
  ([#173](https://github.com/saworbit/hammerforge/issues/173)).
- **A project could define a custom point entity and never be able to place
  it.** `HFDock._load_entity_definitions()` opened its own hard coded file
  directly while `_populate_brush_entity_classes()` used the merged loader, so
  `res://hammerforge_entities.json` reached the brush dropdown and
  `level_root.entity_definitions` but not the Objects palette. Both pickers read
  the same merged set now, through `HFEntityDef.load_merged_raw_entries()`,
  which keeps the `label`, `preview` and `category` keys the palette renders
  from and the typed loader drops. The path follows the active `LevelRoot`'s
  `entity_definitions_path`. Two things fell out of the same function: the
  `{"entities": [...]}` form of the file returned before the palette was ever
  built, and brush entities were being listed in the point palette where they
  cannot be placed ([#175](https://github.com/saworbit/hammerforge/issues/175)).
- **Texture lock drifted the texture off a rotated face instead of holding it.**
  `_apply_uv_transform()` rotates before it scales and offsets, so a brush move
  has to be rotated the same way before it compensates `uv_offset`.
  `adjust_uvs_for_transform()` subtracted the raw delta, so a face at a quarter
  turn moved 2 along X shifted its texture vertically. `hf_carve_system.gd`
  already had this right and the two now produce the same value
  ([#141](https://github.com/saworbit/hammerforge/issues/141)).
- **Running the mouse down the undo history pumped the dock layout.** The hover
  preview was an in flow child of the browser's `VBoxContainer`, so showing it
  reserved 160 by 96 pixels at the bottom of the list and hiding it took them
  back: the panel's minimum height went 175px to 275px and back on every row.
  It is `top_level` now, outside the box layout, parked beside the hovered row
  and pulled back inside the window near an edge
  ([#142](https://github.com/saworbit/hammerforge/issues/142)).
- **The contextual toolbar ran off both sides of the viewport when it did not
  fit.** With a brush selected it measures 940px unwrapped, and the 3D viewport
  is narrower than that as soon as a dock is open — centring something wider
  than what it is centred in just hangs it off both ends, with the controls at
  each end unreachable. Its sections wrap now, and placement caps an overlay to
  the viewport it floats over. Measured at a 709px viewport: laid out at 693px
  across four rows, with every button inside the viewport instead of 115px of
  toolbar hanging off each side. A toolbar that fits still keeps its own width
  rather than stretching to fill.
- **Every keybinding in the command palette was clipped to its first character
  or two** — `Ctrl+Shift+Enter` rendered as `Ctr`, `Shift+P` as `Sh`. The binding
  label was anchored with `PRESET_CENTER_RIGHT`, which puts a control's top-left
  *corner* on that point rather than aligning its right edge to it, so each label
  began at the row's right edge and ran past it for the scroll container to clip.
  Only the single-key bindings looked right, and then only just: `Q` overflowed
  its 300px row by one pixel. The label now stretches the row with its text
  right-aligned and an 8px inset, so it holds that inset at any palette width.
- **The 3D toolbar resized itself, and the viewport moved with it.**
  `CONTAINER_SPATIAL_EDITOR_MENU` is a plain `HBoxContainer` and the 3D viewport
  gets whatever height is left under it. Every control Godot puts in that row is
  a fixed 29px; the shortcut HUD was the tallest child, so the row's height was
  the HUD's height — and the HUD renegotiated it on every mode change and every
  mode hint. Measured in the editor: 46px with a one-line hint, 49px with none,
  63px with the two-line draw hint, and hints appear and expire on a timer, so
  the viewport slid under the cursor with nobody touching anything. The three
  labels ran at three different font sizes, `MODE_HINTS["draw_idle"]` carried a
  newline that quietly made the row two lines, and the row had no height floor.
  One `ROW_FONT_SIZE` for every label, `_pin_row_height()` measuring a single
  line from the theme, and `_show_hint` collapsing newlines. Now 46.0px in every
  mode and hint state. The status strip had the same fault sideways — its
  summary rewrites on a two-second poll, swinging 76px to 155px and dragging
  everything to its right along the row — and is now a fixed width with the
  numbers still on its tooltip.
- **One side of a box flickered while you dragged it.** The preview brush is
  parented under `draft_brushes_node` for the whole drag and stands a full grid
  step tall, and draft brushes carry no physics body, so `_raycast` always falls
  through to `pick_face_from_ray` for the placement ray. The preview was not
  excluded there, so a drag heading *away* from the camera met the preview's own
  roof before the construction plane: the hit sits nearer the eye, the box pulls
  back off the cursor, the next ray misses it and the box springs out again.
  Drag towards the camera and nothing is in the way, which is why it only bit
  sometimes. Pinned by a test in which a still cursor moved the box's Z edge from
  8.0 to 7.5. The same chokepoint feeds hover and object picking, so during a
  drag those were latching onto the preview instead of real geometry too. The
  snap system already skipped the preview; picking now does the same.
- **Viewport overlays were laid out as toolbar items.** The contextual toolbar,
  the command palette and the cursor property popup were added to the 3D toolbar
  row, which is a layout container, so it reserved each one's full minimum size
  out of the space the viewport was going to get: the toolbar's minimum was
  (800, 46) at rest and (1136, **380**) the instant the palette opened. They now
  parent to the `Control` Godot passes to `_forward_3d_force_draw_over_viewport`
  — the viewport's own rect, which reserves nothing and positions nothing — with
  placement in one table, `HFPluginOverlays.VIEWPORT_OVERLAY_ANCHORS`, centred
  against the size each overlay reports and re-anchored when that size moves —
  the contextual toolbar is 41px wide with nothing selected and 940px with a
  brush selected, so anchoring it once while empty left it running off the side
  of the viewport. That rect
  is also the space `event.position` is measured in, so `hf_quick_property`'s
  `position` and `hf_radial_menu`'s `PRESET_FULL_RECT` are no longer overwritten
  by the container on its next re-sort. Toolbar minimum is now (458, 46) and
  stays there with every overlay open.
- **`brush_changed` never fired.** The signal was declared on `LevelRoot` and
  emitted nowhere, while `HFSubtractPreview` connected to it, so the live
  subtract overlay listened to a signal that could not arrive and only refreshed
  when a brush was added or removed. `tag_brush_dirty()` emits it now, which is
  the one call every transform, material, UV, paint and vertex mutation already
  makes. It fires on every tag rather than only the first, because the dirty set
  is not cleared until a bake and a preview following a drag needs each step.
  The preview connects only while enabled and `show_subtract_preview` defaults
  off, so nothing is emitted into an empty room by default.
- **Box faces exported to `.map` carried another face's texture and UV settings**
  ([#113](https://github.com/saworbit/hammerforge/issues/113)): `MapIO._box_to_map_lines`
  walked its plane table with the same counter it used to index `brush.faces`, but the
  two tables were in different orders. The plane table now runs Right, Left, Top, Bottom,
  Front, Back, the order `DraftBrush._build_box_faces` builds them in. The exported plane
  points are unchanged; only the face data paired with each one moves.
- **The far corner cap of a bevel faced into the brush**
  ([#112](https://github.com/saworbit/hammerforge/issues/112)): `HFBevelSystem.bevel_edge`
  wound both endpoint caps the same way. The two arcs are translated copies of each other,
  so both normals pointed the same direction and backface culling hid one of them, which
  also broke CSG and collision. Each cap is wound against the direction leading away from
  the edge now, so it holds for any edge orientation.
- **Clip and Hollow previews drew for brushes the tools refuse**
  ([#116](https://github.com/saworbit/hammerforge/issues/116)): a cylinder or a rotated box
  showed a valid-looking wireframe and then failed with an error toast on click, and rotated
  boxes drew their wireframes unrotated in global space. Both previews ask `can_clip_brush`
  and `can_hollow_brush` now, the same validators the tools run, so the preview and the
  operation cannot disagree. That also removed the second copy of the split-bounds and
  wall-thickness rules the previews were carrying.
- **Play from Camera left a bogus step on the undo stack**
  ([#114](https://github.com/saworbit/hammerforge/issues/114)): the spawn is parked at the
  editor camera only long enough to bake and launch, and every exit path puts it back, but
  the move was also recorded as an undo action. Undo consumed a step without changing
  anything and Redo moved the spawn to the camera for good. `record_spawn_camera_undo` and
  its `dock.gd` wrapper are gone with the call. The spawn-create and spawn-fix undo actions
  stay, because those changes persist.
- **`gdformat` could not parse the test suite, and CI never asked it to**
  ([#115](https://github.com/saworbit/hammerforge/issues/115)): a raw newline sat inside a
  double-quoted string in `tests/test_bugfix_regressions.gd`, which GDScript does not allow.
  The format step only covered `addons/hammerforge/`, which is why it went unnoticed. It
  covers `tests/` as well now, and the eight files that surfaced once the check was widened
  are formatted.
- **Snap candidate rebuilds formatted a string per vertex on every mouse move**
  ([#122](https://github.com/saworbit/hammerforge/issues/122)): `_face_snap_geometry` runs
  for every non-box brush on every motion event during a drag and keyed vertices and edges
  by formatted string. Keys are `Vector3i` and `Vector2i` now, which hold the same
  millimetre tolerance without formatting anything. Measured over 300 brushes and 200 motion
  events with Vertex, Edge and Perpendicular on: a mix with one brush in ten non-box went
  from 10.33 ms to 3.97 ms per event, and an all-non-box level from 77.46 ms to 14.52 ms.

- **The shortcut HUD stopped overlapping the viewport context toolbar.** It is
  parented into the 3D toolbar, which is a `BoxContainer`: it lays its children
  out itself, sizes them to their minimum, and ignores the anchors a floating
  overlay sets. A plain `Control` reports a minimum of zero, so the HUD was
  handed a zero-width slot, drew its seven lines out of it, and had six painted
  over by the viewport while the seventh landed on top of the context toolbar.
  It now claims the space it draws into and spends its one row on the line that
  changes — the active hint, or the primary action for the current tool — with
  the full list on the tooltip. Its three labels also shared a single
  `MarginContainer` rect, which gives every child the same rectangle; they are a
  row now, rather than being kept apart by right-alignment and a leading newline.
- **Fractional grid snaps displayed as `Grid: %g`.** GDScript has no `%g`
  specifier, so every non-integer snap printed the specifier verbatim and raised
  an engine error alongside it.

### Changed
- `HFBrushSystem._adjust_face_uvs_for_rotation()` moved to
  `HFTransformSystem.adjust_face_uvs_for_rotation()`, where it finally has a
  caller. It was written for rotation and had been dead since it landed.
- `HFPluginEditActions` gained `collect_managed_targets()`; `nudge_selected()`
  and the three transform actions now share one selection classifier instead of
  repeating it.
- **Snap geometry is cached per brush**
  ([#122](https://github.com/saworbit/hammerforge/issues/122)): deduping a brush's
  faces was the remaining cost in a snap query, and it ran for every non-box brush
  on every mouse motion event. The result lives in brush space, so it survives
  every drag, rotate and resize of everything around it. Entries are keyed by
  brush id, stamped with the node instance, face count and size, and dropped on
  `brush_changed` or `brush_removed`. A brush with no id is never cached, since
  nothing would name it to invalidate it. Measured over 300 brushes and 200 motion
  events with Vertex, Edge and Perpendicular on: a mix with one brush in ten
  non-box went from 4.13 ms to 3.00 ms per event, and an all-non-box level from
  15.41 ms to 3.49 ms. Against the original string-keyed version those levels
  started at 10.33 ms and 77.46 ms.

- **Preview box outlines go through `HFOutlineUtil`**
  ([#121](https://github.com/saworbit/hammerforge/issues/121)): `_build_wireframe_mesh` was
  written four times, byte identical, in the carve, clip, hollow and subtract previews, each
  baking world coordinates into a fresh `ImmediateMesh` per box per rebuild. They share one
  unit-box outline now and place it with `aabb_box_transform()`, so box previews render
  through the same path as the gizmo outlines.
- **The path and polygon tools have one raycast each**
  ([#124](https://github.com/saworbit/hammerforge/issues/124)): both carried byte-identical
  copies of `_raycast_ground` and `_raycast_to_y_plane`. The first was a `has_method` wrapper
  around `root._raycast` and is gone. The second had no shared equivalent, so it moves to
  `LevelRoot.screen_ray_to_y_plane` beside `construction_plane_intersection`, unchanged.
- **Brush lookup and face keys call their owner**
  ([#123](https://github.com/saworbit/hammerforge/issues/123)): the bevel and displacement
  systems wrapped `root.find_brush_by_id` in a `has_method` guard, and the paint input, dock
  and tutorial wizard did the same inline. `LevelRoot` always has that method, so the guard
  only hid a null root the callers already check. Face keys had three implementations that
  agreed on the answer; `HFBrushSystem.face_key` is static and takes `Node` now, and the
  other two call it. `HFPluginSelectionCommands.face_key_for` gains the null guard it never
  had.

- **The power-user overlay toast names both places that can turn them on.** The
  switch lives in the Console's Controls tab and in the dock under
  Test -> Settings; the toast pointed only at the dock, which was the whole
  story before the Console existed. The menu path inside it is joined with
  non-breaking spaces so the toast never wraps between "Test" and "Settings" and
  leaves the arrow dangling at a line end. The user guide documented the radial
  menu, coach marks and the replay timeline without mentioning they are opt-in at
  all, so pressing the documented key produced a toast instead of the feature.
- **HammerForge is findable in the editor.** It now takes a place in the
  main-screen switcher with its own mark — the one row of the editor chrome that
  draws a plugin icon at all. Godot 4.7's bottom panel is text-only, and a docked
  control's icon lives on the `EditorDock` wrapper, which needs `force_show_icon`
  before it will draw. The left dock tab said "Dock" and carried no icon; it now
  says **HammerForge** and wears the mark.
- **`HFLog.warn()` mirrors to the Console** through an optional sink, and
  `LevelRoot`'s `user_message` signal now reaches the Log tab as well as a toast
  — toasts fade, and a failed bake could not be reconstructed afterwards.
- **The brand build emits the addon's lockups.** `docs/brand/build.py` now writes
  `addons/hammerforge/branding/hf_lockup_{dark,light}.svg` and the 32px
  `hf_mark_editor.svg` the switcher draws, alongside the rest, so nothing the
  editor shows can drift from the brand set. The switcher renders a plugin icon
  at its texture size, so a 64px mark lifted the whole top bar. `docs/brand/png/*.import`
  is now ignored rather than reappearing untracked after every project import.


## [0.3.0] - 2026-09-03
### Added
- **PBR channels survive material atlasing** ([#24](https://github.com/saworbit/hammerforge/issues/24)): `HFMaterialAtlas` now packs normal, roughness, metallic, and emission maps into parallel atlases over the albedo layout, so one set of remapped UVs addresses all of them. Materials that supply no map for a slot contribute a flat tile carrying their own scalar. A slot the atlas cannot represent faithfully — suppliers disagreeing on `normal_scale`, on a texture-channel selector, or on a multiplier that would distort untextured tiles — is reported in `AtlasResult.skipped_channels` **and** in the editor log via `HFLog.warn()`, instead of being silently dropped. A supplied texture that cannot be read drops the whole slot rather than substituting a flat tile. Slots nobody uses cost nothing.
- **`HFLog` capture coverage** (`tests/test_hf_log.gd`, 6 cases): warning capture, suppression, buffer lifetime, and the idle-path regression below.
- **Atlas benchmark** (`tools/benchmark_bake_atlas.gd`): compares the gutter fill against the per-texel loop it replaced and reports `build_atlas()` with and without PBR slots.
- **PBR atlas coverage** (`tests/test_material_atlas_pbr.gd`, 32 cases): per-slot packing, flat tiles for non-suppliers, carried-across settings, every skip reason, shared layout across atlases, resampling, and non-RGBA8 sources.
- **Paint hot-path benchmark** (`tools/benchmark_paint_hot_paths.gd`): reports per-texel access costs, cold-vs-cached `FaceData.get_painted_albedo()`, and how a sculpt-smooth stamp scales with brush radius. Run it before and after any paint performance change so the numbers in a PR are reproducible.
- **Coverage for the paint hot paths** (`tests/test_paint_hot_paths.gd`, 39 cases): `SurfacePaint.paint_at_uv`, `FaceData.get_painted_albedo` (blend modes, opacity, layer stacking, resizing, cache invalidation), and `HFPaintTool._apply_terrain_brush` (raise/lower/smooth/flatten, falloff, wrapping, clamping, dirty chunks). None of these had direct tests before.
- **Project governance and contributor onboarding:** added `SECURITY.md` (private vulnerability reporting, with level-file parsing, unintended file writes, secret handling, and `HFIORuntime` called out as in-scope) and `CODE_OF_CONDUCT.md` (adapted from Contributor Covenant 2.1). Added GitHub issue forms for bugs and features, a pull request template mirroring the CONTRIBUTING checklist, and Dependabot for GitHub Actions. Open issues are now grouped under milestones and labelled by `area:` matching the dock tabs; README and CONTRIBUTING link to good-first-issue, help-wanted, and Discussions entry points.
- **Snap-to-perpendicular** (dock **P**): drop the cursor onto the closest point on a brush AABB edge, so offsets stay 90° to that edge.

### Fixed
- **Polygon and Path placement use the shared viewport hit and snap pipeline** ([#65](https://github.com/saworbit/hammerforge/issues/65)): the first point lands on the nearest exact visible brush surface, falls back to the forward construction plane, and applies every enabled snap mode through `LevelRoot._snap_point()`. Later points start from the first point's horizontal plane before passing through the same snap pipeline.
- **Prefab instance bookkeeping resolves every managed member** ([#66](https://github.com/saworbit/hammerforge/issues/66)): brushes in Draft, Pending Cuts, and Committed Cuts are found through a dedicated managed-brush lookup, while point and brush entities share the entity-system lookup. Removing or saving an instance now warns when a recorded member is missing instead of silently producing a partial result.
- **`HFLog.warn()` no longer prints a spurious engine error:** `_capture_warning()` called `Engine.get_meta(key, null)`, and `Object.get_meta()` only honours a default that is not null — otherwise it fails and returns `Variant()`. Outside a test capture the key is absent, so every warning in the running editor was accompanied by "Method/function failed. Returning: Variant()".
- **Surface painting works again:** `SurfacePaint.paint_at_uv()` called `Image.lock()` / `Image.unlock()`, which are Godot 3 API removed in Godot 4. The call aborted the function before any texel was written, so every surface paint stroke was silently discarded.
- **Face composites no longer touch the source texture:** `get_painted_albedo()` resized the image returned by `Texture2D.get_image()` in place when it matched no cached entry, and could not read a VRAM-compressed source. It now copies, decompresses when needed, and then resizes.
- **Playtest exports are complete and playable:** exported scenes include `PlaytestPlayer` at the active spawn pose, keep nested baked mesh/collision and brush I/O nodes through recursive ownership, and preserve source transforms when moving baked trees, entities, and `DefaultSun` under the packed scene root.
- **MultiMesh bake keeps instance placement:** source transforms are converted into baked-container space, and `TRANSFORM_3D` is selected before instance allocation.
- **Brush entity I/O participates everywhere:** bake dispatcher detection, exported-scene detection, connection listing, dangling cleanup, and target rename reconciliation all include tied brush entities.
- **Entity container validation uses the real LevelRoot property:** `HFValidation.has_entity_container()` now checks `entities_node`.
- **Polygon height and path trim edge cases:** downward polygon height input stays positive, and auto-trim can assign material palette slot 0.
- **Tied `func_detail` / trigger brushes bake again:** they stay out of world CSG, then a post-pass emits detail meshes + collision and trigger `Area3D` volumes (including copied I/O metadata).
- **`.map` brush entities round-trip:** `func_detail` / `func_wall` / triggers export as their own entity blocks and import with `brush_entity_class` set.
- **`.map` point entities keep their keys:** export writes `entity_data` (angle, targetname, etc.) alongside classname/origin.
- **`.hflevel` saves no longer truncate the destination first:** writes go to a `.writing` sidecar and rename into place. The write thread snapshots autosave settings on the main thread and is joined when LevelRoot exits.
- **`.hflevel` compression works:** `hflevel_compress` now emits an `HFLEVEL1C` deflate payload; uncompressed `HFLEVEL1` files still load.
- **Test Level wires entity I/O by default:** `bake_wire_io` defaults to true so connections fire without an Inspector toggle.
- **HFIORuntime lookup is O(1):** dispatchers join the `hf_io_dispatcher` group; tree walks are fallback only.
- **Wireframe bake preview reuses one compiled shader** instead of parsing GLSL every bake.
- **PlaytestFPS** reads gravity with a 9.8 fallback and shows a reticle plus an Esc pause/controls overlay.
- **Displacement meshes use averaged vertex normals** instead of flat per-triangle shading.
- **Prefab capture uses the combined visual AABB center** so oversized brushes don't skew the placement origin.
- **History thumbnails skip GPU readback** when the History section is hidden, and new rows append instead of rebuilding the list.

### Changed
- **Viewport input, numeric entry, selection, edit-action, drag-and-drop, and overlay behavior use focused plugin modules** ([#41](https://github.com/saworbit/hammerforge/issues/41)): `_forward_3d_gui_input()` delegates to `plugin_viewport_input.gd`, which owns native RMB camera-session arbitration and input ordering. Numeric draw/extrude dimension parsing, live preview, and commit delegate to `plugin_numeric_input.gd`; floor, surface, and displacement painting delegate to `plugin_paint_input.gd`; draw, extrude, motion, and prefab hover delegate to `plugin_pointer_tools.gd`; native object/Face Select pointer arbitration and face marquee picking delegate to `plugin_selection_input.gd`; EditorSelection synchronization, managed-owner normalization, group expansion, and mixed-selection scope guards delegate to `plugin_selection_state.gd`; undoable managed-object and brush geometry commands delegate to `plugin_edit_actions.gd`; entity, brush-preset, prefab, and material viewport drops delegate to `plugin_drop_handler.gd`; power-user overlay lifecycle, vertex rendering, marquee drawing, quick-property commits, and coach-mark routing delegate to `plugin_overlays.gd`.
- **Dock services are split by responsibility** ([#22](https://github.com/saworbit/hammerforge/issues/22)): file-dialog and import/export callbacks live in `dock_file_handler.gd`, visgroup/group/cordon workflows live in `dock_visgroup_handler.gd`, and settings plus `LevelRoot` signal wiring live in `dock_connections.gd`. `dock.gd` retains thin compatibility delegates.
- **Exported levels skip editor-only subsystem initialization** ([#21](https://github.com/saworbit/hammerforge/issues/21)): export templates keep the brush, entity, bake, paint, and file core needed to load and run levels, but do not load or construct grid, drag, snap, selection, preview, prefab-authoring, validation, spawn-authoring, displacement, bevel, undo, or other editor services. Editor builds and headless editor tests retain the complete tool graph.
- **Atlas gutter fill uses `blit_rect` / `fill_rect`** instead of a per-texel `get_pixel` / `set_pixel` loop: 4 * GUTTER + 4 native calls per tile rather than one call per gutter texel. Measured 11x faster on a 128px tile, which matters now that each PBR slot builds its own atlas.
- **Face paint composites are memoised** ([#39](https://github.com/saworbit/hammerforge/issues/39)): `FaceData.get_painted_albedo()` caches its result against a key covering `max_size`, layer count, each layer's texture identity/size, blend mode, opacity, and a content hash of its weight image. `rebuild_preview()` runs from 27 call sites — including once per surface-paint sample — and previously recomposited every painted face of the brush each time. Measured on Godot 4.7 at 256x256: 61.7 ms cold, 0.077 ms on a cache hit. Call `invalidate_painted_albedo()` after mutating paint layers through any path the key does not cover.
- **Project documentation matches current `main`:** user-facing tab names, snap modes, playtest export behavior, architecture notes, roadmap priorities, and verified CI totals now agree across the README, guides, spec, and checklists.
- **Merged-mesh bake uses `WorkerThreadPool`** when `bake_use_thread_pool` is on. Surface grouping/transforms run on a worker; `ArrayMesh` assembly stays on the main thread.
- **`.hflevel` stringify/hash/compress run on the write thread.** Capture stays on the main thread; unchanged captures skip the disk rewrite once the hash settles.
- **Test-tab bake/play handlers live in `dock_manage_handler.gd`:** bake, validate, Test Level, spawn, and playtest dock methods are thin wrappers around `HFDockManageHandler`.
- **Objects-tab entity handlers live in `dock_entity_handler.gd`:** property rebuild, create-entity, and I/O/wiring dock methods are thin wrappers around `HFDockEntityHandler`.
- **Build-tab brush handlers live in `dock_brush_handler.gd`:** displacement, bevel, hollow, clip, floor/ceiling, duplicate-array, and tie/untie dock methods are thin wrappers around `HFDockBrushHandler`.
- **Paint-tab handlers live in `dock_paint_handler.gd`:** layer, heightmap, scatter, sculpt, region, and terrain-slot dock methods are thin wrappers around `HFDockPaintHandler`.
- **HUD and context-toolbar state live in `plugin_hud.gd`:** `_update_hud_context()` and `_update_context_toolbar_state()` are thin wrappers around `HFPluginHud`.
- **Vertex/edge input lives in `plugin_vertex_input.gd`:** `plugin._handle_vertex_input()` is a thin wrapper around `HFPluginVertexInput.handle()`.
- **Viewport keymap lives in `plugin_input_router.gd`:** `plugin._handle_keyboard_input()` is a thin wrapper around `HFPluginInputRouter.handle_keyboard()`.
- **Plugin command dispatch is one module:** context toolbar, hotkey palette, viewport menu, and radial menu all call `HFPluginCommands.execute()` instead of three copy-pasted match blocks.
- **Godot MCP Native v1.0.8:** vendor snapshot updated from 1.0.7-pre1 (`2e138ed`). HTTP still binds to `127.0.0.1` unless remote access is enabled.
- **Live CSG subtract preview:** overlapping additive/subtract DraftBrushes show the actual CSG cut volume after a two-frame bake. Mesh-bound AABB wireframes remain as the immediate fallback. Full-level CSG of every brush is still out of scope.
- **Heightmap convert uses authored meshes:** conversion rasterizes additive mesh bounds (including displacement height) and skips subtract brushes so heightmaps do not fight Source-style displacements or cutters.
- **Subtract preview sees DraftBrushes** and uses mesh bounds instead of skipping non-CSGShape3D nodes.
- **Per-project entities:** `res://hammerforge_entities.json` overlays the plugin entity list (same classname wins).
- **`.map` fidelity:** rotated/complex brushes import and export as CUSTOM face planes instead of cylinders/boxes.
- **BrushManager is a list mirror:** `clear_brushes()` no longer frees nodes. `HFBrushSystem` owns brush lifetime; multi-brush create/delete/nudge now batch LevelRoot signals.
- **Snap-to-edge:** new EDGE snap mode (dock **E** / Edges) snaps to AABB edge midpoints of existing brushes.
- **Core-loop freeze:** the default editor is Draw → material → entity → bake → Test Level. Radial menu, coach marks, and operation replay are gated behind **Test → Settings → Power-user overlays** (off by default). Unused welcome-panel, BrushPrefab, debug_heightmap, and archived quadrant-view scripts were removed. `BrushManager` is a null-safe legacy mirror of `HFBrushSystem`'s brush cache.

### Fixed
- **MCP scanner no longer floods the editor Output:** `detect_broken_scripts` and on-disk `validate_script` use Godot's compiled resources instead of reloading stripped copies, which broke relative `preload()` and printed false parse errors.
- **Selection/widget arbitration follow-through:** a native transform/property widget or HammerForge resize handle now owns the complete mouse and keyboard stream before marquee or nudge handling can run. Lost native selection releases clear the complete session, application focus recovery settles external pointer captures, and Polygon height drag cannot mutate or commit on an unrelated later release. Mixed Godot/HammerForge and heterogeneous brush/entity selections are guarded all-or-nothing across dock handlers, delayed confirmations, shortcuts, and viewport action surfaces.
- **Constrained radial primitives and resilient entity targets:** sphere/cylinder/cone/capsule draw bounds are recentered from the final normalized size so they do not drift sideways or float above the construction plane. Capsule height stays at least its diameter while Y-handle resizing retains the opposite-face anchor. Odd-sided pyramids/prisms now fill a centered requested AABB so visible geometry, outlines, bake output, and handles agree. Visible null, broken, and line-only entity previews receive a restrained proxy at their real nested/top-level transform—even beside healthy sibling visuals—while hidden previews and hidden parents leave no invisible target.
- **Reliable incremental Bake Changed state:** an ID-keyed signature tracker reconciles Godot-owned transform/Inspector commits plus native Undo/Redo, including nested FaceData material, UV, vertex, paint-image, and displacement resource edits. Nudge, floor/ceiling moves, override and face materials, UV changes, surface-paint layers, convex clipping, and vertex replay now tag only the brushes they actually change, so visible edits cannot be silently skipped by an incremental bake.
- **Clean brush visuals and leak-proof previews:** rapid drawing/resizing no longer leaves dozens of auto-renamed green wireframe copies or exposes the drag's intermediate sizes. Ordinary additive brushes now render without an always-on triangle wireframe; subtract/entity overlays are reused one-per-kind and legacy leaked children are removed synchronously. Subtract brushes use the same sparse, depth-aware semantic lines instead of a dense render cage. Hover and selection share that semantic outline source: angular and custom shapes keep true boundaries/creases without coplanar triangle diagonals, while curved primitives use sparse shape-specific profiles instead of box or render-wireframe fallbacks.
- **Truthful live visual refresh:** whole-brush/editor materials and brush-entity tie/untie changes now appear immediately, including through restore, hollow, merge, and carve paths. Unmaterialed polygon/path/custom brushes render their actual face geometry instead of a fallback box; scaled and offset shapes get accurate hover bounds; a selected brush no longer receives a second coincident hover outline. Fixed-name entity previews and floor/sun state restoration also detach replacements safely within the same frame.
- **Baked geometry lifecycle:** persisted `BakedGeometry` is re-adopted when a scene opens, full-bake replacement releases the old name before installing the new container, and recognized legacy anonymous bake roots—including face-material and heightmap output—are reconciled conservatively. Repeated bakes no longer accumulate saved `@Node3D@...` containers, while unrelated anonymous nodes are preserved.
- **Issue #5 — RMB camera navigation:** HammerForge now keeps native RMB look available regardless of brush, object, face, or unrelated scene-node selection. After an idle RMB press is passed to Godot, the complete session—including motion, WASD flight, shortcut-hook keys such as Ctrl+Arrow/Escape, mixed mouse input, and release—bypasses HammerForge actions and raycasts. Active draw, extrude, Face Select marquee, vertex, polygon, and path interactions can still consume the initial RMB press to cancel or step back.
- Viewport input forwarding is now enabled explicitly instead of making `_handles()` claim unrelated selected nodes. Measure snap-reference assignment moved from plain RMB to Ctrl+Click, and quick-property popups dismiss without swallowing RMB/MMB/wheel navigation.
- **Deterministic selection and gizmo ownership:** Godot's `EditorSelection` is now authoritative, including a genuine empty selection—HammerForge no longer keeps a hidden stale brush selection after the Scene tree or viewport is cleared. Every ordinary Object Select click and empty-space marquee now uses Godot's native viewport pipeline; Shift keeps Godot's additive/active-selection behavior and Ctrl/Cmd remain Godot-owned. Filled collision triangles make real brush faces and visible nested entity previews generous native targets, while truly geometry-less entities get a quiet one-unit marker. HammerForge normalizes internal preview children and grouped brushes only after the native result completes. Explicit cancel, buttonless motion, and application/window focus recovery clear stale selection, RMB, paint, vertex, and gizmo ownership without double-settling Godot's widgets.
- **Focused Face Select and safe managed edits:** Entering Face Select now switches to Select, turns Paint off, and hides object transform/resize gizmos. Shift adds faces and Ctrl/Cmd toggles them; marquee accepts a projected candidate only when the canonical pick confirms that same face is frontmost and visible. Leaving Paint, choosing an incompatible built-in/external tool, entering vertex edit, selecting an object in the Scene tree, or using the staged Escape flow exits without leaving hidden modal state. Delete, Duplicate, and nudge now handle canonical `DraftEntity` selections as managed objects alongside brushes. Mixed HammerForge + Godot selections are blocked consistently across keyboard, context toolbar, viewport context menu, hotkey palette, and radial dispatch before a partial managed edit can corrupt IDs, caches, or undo state.
- **Scale- and shape-correct brush resize handles:** Face-handle distance and grid snap are now evaluated in world units, converted back through the transformed local-axis scale, and keep the opposite face fixed under rotated or non-uniformly scaled parents. Sphere handles keep all dimensions uniform; cylinder, cone, and capsule X/Z handles adjust one shared radius while Y remains independent. Collapsed/non-finite axes are rejected safely. Lost-release recovery restores and freezes the original preview, releases its local latch after a bounded deferred recovery, and suppresses any late native commit; completed drags create one undo step, while no-op and cancelled drags create none.
- **Accurate picking, placement, and vertex movement:** brush AABBs are now broad-phase only—click, hover, face tools, and surface-placement fallbacks resolve the exact visible face triangles, so empty space inside a wedge, cone, pyramid, curved, or custom brush cannot select, occlude, or receive a dropped item. Picks ignore nodes and preview visuals hidden by visgroups, traverse internal entity preview children, compare brushes and entities by the same nearest world-ray distance, and remain correct under scaled transforms. Vertex and edge drags project from the picked world anchor onto a view-facing plane (or a camera-stable plane containing the requested world-axis lock), with degenerate head-on projections rejected instead of jumping.
- Project-local Codex client state under `.codex/` is now ignored; the authenticated Godot MCP setup is documented as machine-local contributor configuration.

### Added
- **Code-quality utilities — simplification phase 1** (May 2026): Eight new shared utility
  classes extracted from the dock + plugin monoliths to reduce duplication and improve
  testability. None change runtime behavior; all existing call sites delegate.

  - `systems/hf_system.gd` — `HFSystem` base class (lifecycle: `_init(root)`, `destroy()`,
    `clear()`, `set_enabled()`, `is_enabled()`, `_has_nodes(names)`). The four preview systems
    (`HFSubtractPreview`, `HFCarvePreview`, `HFClipPreview`, `HFHollowPreview`) now extend this
    base. New subclasses must use `extends "hf_system.gd"` (path-based) rather than
    `extends HFSystem`, because `class_name` registration isn't resolved before the editor
    has scanned scripts.
  - `ui/hf_ui_factory.gd` — `HFUIFactory` static factory with `make_label_row`, `make_spin`,
    `make_check`, `make_button`, `make_option`, `make_separator`, `make_spin_row`,
    `make_section_header`. `dock.gd`'s `_make_*` helpers now delegate; 100+ existing call
    sites in tab builders flow through it transparently. `selection_tools_builder.gd` and
    `entity_tab_builder.gd` migrated to call HFUIFactory directly.
  - `hf_validation.gd` — `HFValidation` static guards: `is_valid_root`, `has_draft_containers`,
    `has_entity_container`, `has_baked_container`, `has_node`, `has_nodes`, `require_nodes`.
    Applied to `HFBrushSystem.apply_pending_cuts` and `restore_committed_cuts` as
    demonstration; broader application deferred (single-property guards are 1-line either way).
  - `ui/hf_editor_theme.gd` — `HFEditorTheme` static helpers for editor icons/colors/styleboxes:
    `find_editor_icon`, `has_editor_icon`, `get_editor_icon`, `get_editor_color`,
    `resolve_stylebox`, `style_toolbar_button`. Six dock helpers now delegate.
  - `ui/hf_undo_nav.gd` — `HFUndoNav` per-scene UndoRedo navigation: `get_scene_history_id`,
    `get_scene_undo_redo`, `navigate_to_version`. Three dock helpers delegate.
  - `ui/hf_entity_prop_utils.gd` — `HFEntityPropUtils` collapses the
    `DraftEntity.entity_data` vs `Node3D.set_meta("entity_data", ...)` dual-write pattern.
    Four dock entity-prop handlers and the entity_type lookup at the top of
    `_rebuild_entity_props` reduced from ~85 lines to ~16 lines of delegates.
  - `ui/hf_tooltip_text.gd` — `HFTooltipText` static catalog of 100+ tooltip strings keyed by
    dock control-property name. `dock._apply_all_tooltips` reduced from ~200 lines to
    3 lines (`HFTooltipText.apply_all(self)` + `apply_snap_buttons(snap_buttons)`).
  - `plugin_dialogs.gd` — `HFDialogManager` instance class. Tracks `ConfirmationDialog` /
    `AcceptDialog` instances with auto-removal on `tree_exiting`, frees all on
    `cleanup()`. `plugin._add_confirmable_dialog` and `_cleanup_pending_dialogs` delegate.

  **Eight new test files, 75+ cases:** `test_ui_factory.gd`, `test_hf_validation.gd`,
  `test_hf_system.gd`, `test_hf_undo_nav.gd`, `test_entity_prop_utils.gd`,
  `test_hf_tooltip_text.gd`, `test_hf_dialog_manager.gd`, `test_hf_editor_theme.gd`.

  **LOC impact:** dock.gd 7,001 → 6,692 (–309, –4.4%); plugin.gd 3,991 → 3,987 (–4;
  responsibility separation rather than line reduction).

  **Two regressions caught in review and fixed:**
  - Mojibake in `dock.gd` (49 sites) caused by a PowerShell `Set-Content -Encoding utf8`
    step used to splice the tooltip-block delegate. Re-encoded existing UTF-8 bytes via
    cp1252 → UTF-8, turning `—`/`→`/`▲`/`•`/`…` into `â€"`/`â†'`/`â–²`/`â€¢`/`â€¦`. One
    case was **behavioral**: the extrude-up color branch at `dock.gd:2302` checks
    `if "▲" in mode_key`; the corrupted `"â–²"` literal would never match. Fixed via
    Python pass that decoded the file as UTF-8 and substituted each known mojibake
    sequence with the correct codepoint.
  - `tests/test_hf_undo_nav.gd` used the Godot 3 `UndoRedo.add_do_method(obj, method,
    args...)` signature. Godot 4 expects a `Callable`. GUT silently skipped the file,
    leaving `HFUndoNav.navigate_to_version` untested. Fixed by switching to closures
    (`func(): counter.append(v)`) and extracting a `_make_ur(steps)` helper. After the
    API fix 3 tests still failed because `UndoRedo.get_version()` starts at 1 in
    Godot 4 (not 0) and increments on each commit, so 3 commits gives version 4 not
    3. Final fix captures `v_top := ur.get_version()` dynamically and asserts relative
    offsets (`v_top - 2`, `v_top + 999`) instead of hard-coding numbers. Added a
    clamp-at-bounds test case (target far below / above the history range) since the
    navigate loop has no explicit cap.

  Files: `addons/hammerforge/systems/hf_system.gd` (new),
  `addons/hammerforge/systems/hf_subtract_preview.gd` (modified),
  `addons/hammerforge/systems/hf_carve_preview.gd` (modified),
  `addons/hammerforge/systems/hf_clip_preview.gd` (modified),
  `addons/hammerforge/systems/hf_hollow_preview.gd` (modified),
  `addons/hammerforge/systems/hf_brush_system.gd` (modified),
  `addons/hammerforge/ui/hf_ui_factory.gd` (new),
  `addons/hammerforge/ui/hf_editor_theme.gd` (new),
  `addons/hammerforge/ui/hf_undo_nav.gd` (new),
  `addons/hammerforge/ui/hf_entity_prop_utils.gd` (new),
  `addons/hammerforge/ui/hf_tooltip_text.gd` (new),
  `addons/hammerforge/ui/selection_tools_builder.gd` (modified),
  `addons/hammerforge/ui/entity_tab_builder.gd` (modified),
  `addons/hammerforge/hf_validation.gd` (new),
  `addons/hammerforge/plugin_dialogs.gd` (new),
  `addons/hammerforge/dock.gd` (modified),
  `addons/hammerforge/plugin.gd` (modified),
  `tests/test_ui_factory.gd` (new),
  `tests/test_hf_validation.gd` (new),
  `tests/test_hf_system.gd` (new),
  `tests/test_hf_undo_nav.gd` (new),
  `tests/test_entity_prop_utils.gd` (new),
  `tests/test_hf_tooltip_text.gd` (new),
  `tests/test_hf_dialog_manager.gd` (new),
  `tests/test_hf_editor_theme.gd` (new).

- **Toolbar Pending Cuts buttons** (Apr 2026): When subtractive brushes are staged in the
  PendingCuts node, the Draw-mode context toolbar now shows **Apply**, **Commit** (apply + bake),
  and **Clear** buttons alongside a count badge ("N pending"). Previously these actions were
  only available in the Manage tab dock, requiring users to leave the 3D viewport. All three
  buttons are disabled during active bakes and refresh immediately after execution.

  Files: `plugin.gd` (modified), `ui/hf_context_toolbar.gd` (modified).

- **Bake Preview toggle** (Apr 2026): A **Bake▷** toggle button in the Brush-selected context
  toolbar triggers an instant wireframe preview bake, showing the final mesh as a cyan wireframe
  overlay before committing. Toggle off to re-bake at full quality. The toggle is:
  - **Undoable**: routes through `HFUndoHelper.commit()` like all other bake paths.
  - **Race-safe**: disabled during active bakes via `dock._bake_disabled` propagation.
  - **State-tracked**: `LevelRoot._last_bake_preview_mode` is persisted in undo snapshots
    (`capture_state` / `restore_state`), so undo/redo correctly restores the toggle state.
  - **Consistent with dock**: a normal dock bake using the Wireframe dropdown also activates
    the toggle; only WIREFRAME (mode 1) maps to the toggle, not Proxy (mode 2).

  Files: `plugin.gd` (modified), `ui/hf_context_toolbar.gd` (modified),
  `level_root.gd` (modified), `systems/hf_bake_system.gd` (modified),
  `systems/hf_state_system.gd` (modified), `systems/hf_brush_system.gd` (modified),
  `dock.gd` (modified).

- **`bake_state_changed` dock signal** (Apr 2026): New `bake_state_changed(baking: bool,
  success: bool)` signal on `dock.gd`, emitted from `_on_bake_started()` and
  `_on_bake_finished()`. Plugin.gd connects to this signal to immediately refresh the context
  toolbar when bake state transitions occur, ensuring `bake_disabled` propagates to all toolbar
  buttons without waiting for an unrelated HUD update.

  Files: `dock.gd` (modified), `plugin.gd` (modified).

- **New HammerForge Level template** (Apr 2026): One-click starter level creation from the
  Manage tab. Creates a floor (CSGBox3D), directional sun light (DefaultSun), and player spawn
  in a single undoable action. Aimed at eliminating the "where do I start?" moment for new users.

  **DefaultSun** is a DirectionalLight3D at (-45, 30, 0) with shadows enabled. It is fully
  tracked by the state system (capture/restore round-trips correctly through undo/redo) and
  is duplicated into Quick Play and Export Playtest scenes so editor and playtest lighting match.

  Files: `level_root.gd` (modified), `systems/hf_state_system.gd` (modified),
  `dock.gd` (modified), `ui/manage_tab_builder.gd` (modified).

- **HFLog test-aware warning wrapper** (Apr 2026): New `hf_log.gd` (`HFLog`) utility class
  that routes runtime warnings through a testable channel. Tests can capture and suppress
  expected warnings via `begin_test_capture()` / `end_test_capture()` / `get_captured_warnings()`
  without polluting the test output. 15 production call sites converted across 5 files
  (hflevel_io, hf_prefab, hf_bake_system, hf_bevel_system, hf_displacement_system).
  5 test files updated with symmetric capture/assert helpers.

  Files: `hf_log.gd` (new), `hflevel_io.gd` (modified), `hf_prefab.gd` (modified),
  `systems/hf_bake_system.gd` (modified), `systems/hf_bevel_system.gd` (modified),
  `systems/hf_displacement_system.gd` (modified), `tests/test_hflevel_io.gd` (modified),
  `tests/test_prefab.gd` (modified), `tests/test_bake_system.gd` (modified),
  `tests/test_bevel.gd` (modified), `tests/test_displacement.gd` (modified).

### Fixed
- **Playtest sun yaw divergence**: The fallback PlaytestSun in `export_playtest_scene()` used
  yaw -30 while the editor convention is +30, causing lighting to flip between editor and
  playtest. Fixed to use consistent (+30) yaw. DefaultSun (from New Level) is now duplicated
  into the playtest scene, so the fallback is only used when no sun exists at all.

- **Gestalt UI grouping & industry-standard keybindings** (Apr 2026): Keybinding alignment with
  Blender/Hammer conventions and visual tool grouping following Gestalt proximity principles.

  **New keybindings (Blender convention):**
  - **E** — Extrude Up (matches Blender's E for extrude). Context-aware: skipped in paint mode
    (E = Erase) and vertex mode (E = edge toggle). U still works as an alternative.
  - **Shift+E** — Extrude Down. Same context guards. J still works as an alternative.
  - **A** — Select All brushes and entities. Clears face selection first to ensure context
    toolbar transitions to object mode.
  - **Shift+A** — Deselect All (brushes, entities, and faces). Uses `clear_face_selection()`
    for proper visual cleanup and signal emission.

  **Context toolbar group labels:** Small muted category headers before each tool cluster
  (Extrude, Modify, Select, UV, Apply, Entity, Mode, Edit, Shape) make it immediately clear
  which tools belong together, following Gestalt proximity/similarity principles.

  **Dock Selection Tools sub-headers:** The flat tool list in the Brush tab's Selection Tools
  section is now organized into labeled sub-groups with centered separator lines: Brush
  Modification (Hollow + Clip), Positioning (Floor/Ceiling), Entity Binding (Tie/Untie),
  and Duplicate Array.

  **Viewport context menu:** Select All / Deselect All added to the common footer (available
  in every context).

  **Command palette:** New "Selection" category header groups Select All, Deselect All, Select
  Similar, and Selection Filters together. Previously these actions were uncategorized and
  invisible in the palette.

  Files: `hf_keymap.gd` (modified), `plugin.gd` (modified), `ui/hf_context_toolbar.gd`
  (modified), `ui/hf_viewport_context_menu.gd` (modified), `ui/selection_tools_builder.gd`
  (modified), `ui/hf_hotkey_palette.gd` (modified).

- **Error prevention & forgiveness** (Apr 2026): Geometry preview overlays and confirmation
  dialogs for destructive operations, reducing accidental mistakes.

  **Carve preview** (`HFCarvePreview`): green wireframe overlay shows the resulting slice pieces
  before committing a carve. Confirmation dialog with Cancel to abort. Covers both hotkey
  (Ctrl+Shift+R) and context toolbar paths.

  **Clip preview** (`HFClipPreview`): cyan wireframe shows the two resulting halves plus a
  semi-transparent orange quad for the split plane. Confirmation dialog before committing.

  **Hollow preview** (`HFHollowPreview`): yellow wireframe shows all 6 wall pieces that would
  result from hollowing. Supports real-time `update_thickness()` for interactive preview.
  Confirmation dialog before committing. Covers both dock button and hotkey (Ctrl+H) paths.

  **Bulk delete confirmation**: deleting 3+ brushes at once shows a confirmation dialog
  reassuring users that Ctrl+Z can undo. Single/dual brush deletes remain instant.

  **Dialog lifecycle safety**: all confirmation dialogs are tracked in `_pending_dialogs` and
  auto-freed on plugin teardown. Confirmed callbacks guard `is_instance_valid(root)` to prevent
  operating on a dead LevelRoot after scene change.

  Files: `systems/hf_carve_preview.gd` (new), `systems/hf_clip_preview.gd` (new),
  `systems/hf_hollow_preview.gd` (new), `level_root.gd` (modified), `plugin.gd` (modified),
  `dock.gd` (modified).

- **Progressive disclosure for Entity I/O** (Apr 2026): Entity I/O and I/O Wiring sections in
  the Entities tab are now context-hidden — they only appear when an entity is selected, matching
  the existing Entity Properties behavior. I/O Wiring also defaults to collapsed. This keeps the
  Entities tab clean during greyboxing and reveals wiring complexity only when you're actively
  editing an entity.

  Files: `dock.gd` (modified), `ui/entity_tab_builder.gd` (modified).

- **Visual system status feedback** (Apr 2026): Classic editor-style visual feedback for brush
  operations, grid awareness, and system state.

  **Operation-coded wireframe colors:** Brushes now use distinct wireframe overlay colors by
  operation type, matching the convention established by Hammer and TrenchBroom:
  - **Green** wireframe + fill for additive (union) brushes.
  - **Red** wireframe + fill for subtractive brushes (unchanged).
  - **Blue** spectrum for brush entities — bright blue for `func_detail`, medium blue for
    `trigger_*`, muted blue for `func_wall`, slate blue for other entity classes.
  - New `_apply_additive_wireframe_overlay()` in `brush_instance.gd` creates a green wireframe
    overlay for additive brushes (mirroring the existing subtract wireframe overlay). Both
    overlays now refresh on face-preview mesh rebuilds to prevent geometry drift.

  **Grid size viewport indicator:** The shortcut HUD (`shortcut_hud.gd`) now displays the
  current grid snap value persistently (e.g. "Grid: 16") in the top-right viewport panel.
  Uses `%g` formatting for exact display at all snap values (including fractional like 0.125).

  **Grid change flash:** When the grid snap value changes, the indicator briefly flashes
  bright yellow-white and fades back over 0.6 seconds, providing immediate visual confirmation
  without requiring the user to look away from the viewport.

  **Grid size hotkeys** (`[` / `]`): Halve or double the grid snap with a single keypress.
  Clamped to 0.125–512 range. Registered as `grid_decrease` / `grid_increase` in `hf_keymap.gd`
  (user-remappable). Shortcut hint added to draw-idle HUD display.

  **Signal-driven HUD sync:** `dock.gd` emits `grid_snap_applied(value)` from both
  `_apply_grid_snap()` and `_on_root_grid_snap_changed()`, ensuring the HUD updates for all
  grid change origins — dock SpinBox, snap buttons, quick-property popup, `[`/`]` hotkeys,
  state restore, or any direct `root.grid_snap` assignment.

  Files: `brush_instance.gd` (modified), `shortcut_hud.gd` (modified), `plugin.gd` (modified),
  `dock.gd` (modified), `hf_keymap.gd` (modified).

### Fixed
- **Test cleanup leaks** (Apr 2026): Fixed test-owned resource leaks in
  `test_brush_to_heightmap.gd`, `test_context_toolbar.gd`, and `test_selection_features.gd`.
  Heightmap tests now register detached converted layers for cleanup; toolbar tests use GUT's
  auto-queue-free path. Orphan/resource leak shutdown errors eliminated.
  Total: **1370 tests across all files**, full suite passes cleanly in 91.7s.

- **Viewport-centric UI** (Apr 2026): Three Fitts's-Law-driven viewport overlays that keep the
  cursor in the 3D viewport instead of traveling to the dock panel.

  **Context Menu** (Space key): A `PopupMenu` with context-sensitive sections based on the current
  selection state (brush/face/entity/draw/vertex). Sections include grid snap presets (1/2/4/8/16/32/64),
  UV operations submenu, draw shapes submenu, and toggle items like Highlight Connected (check item
  that reads and inverts current state). Position is converted from SubViewport to window coordinates
  via `DisplayServer.mouse_get_position() - get_window().position`. Only activates when idle (no
  active drag, paint, or external tool).

  **Radial Menu** (`` ` `` backtick key): A custom `Control` overlay drawing 8 pie sectors via
  `_draw()` — Box, Cylinder, Select, Paint, Vertex, Tex Pick, Measure, Clip. Added to
  `CONTAINER_SPATIAL_EDITOR_MENU` with `PRESET_FULL_RECT`. Center position uses `event.position`
  from `_forward_3d_gui_input` directly (same coordinate space as the overlay canvas — proven by
  marquee overlay). Hover detection via `_segment_at_position()` helper with inner dead zone
  (`INNER_RADIUS = 30`) and outer ring boundary (`OUTER_RADIUS = 120`). Click recomputes segment
  from `event.position` at click time instead of trusting stale hover state. Dismiss via
  Escape / backtick / RMB. While active, the radial intercepts all input at the top of
  `_forward_3d_gui_input` before paint/vertex/external tool handlers.

  **Quick Property Popups** (double-tap G G / B B / R R): `PanelContainer` with labeled SpinBoxes
  for rapid numeric entry without leaving the viewport. Three property types: Grid Snap (1 spinbox),
  Brush Size (3 XYZ spinboxes), Paint Radius (1 spinbox). Positioned in overlay space with bounds
  clamping. Auto-dismiss on Enter/Escape; click-away dismiss handled by plugin.gd (checks
  `get_rect()` against `event.position`, consumes the dismissing click).

  **Integration:**
  - Unified `_dispatch_viewport_action()` in plugin.gd handles all action strings from context menu,
    radial, context toolbar, and command palette.
  - Keybindings configurable via `hf_keymap.gd` (`context_menu`, `radial_menu` actions in "Tools"
    category). `load_or_default()` merges missing default bindings into existing user JSON files.
  - Command palette gains `context_menu` and `radial_menu` actions with idle-state gray-out.
  - Theme-aware colors via `HFThemeUtils`.

  Files: `ui/hf_viewport_context_menu.gd` (new), `ui/hf_radial_menu.gd` (new),
  `ui/hf_quick_property.gd` (new), plugin.gd (modified), hf_keymap.gd (modified),
  `ui/hf_hotkey_palette.gd` (modified).

- **Automated occluder generation** (Apr 2026): New bake pass that analyzes baked mesh geometry
  to automatically generate `OccluderInstance3D` nodes for runtime occlusion culling.

  Coplanar triangles from baked meshes (including chunked `BakedChunk_*` hierarchies) are grouped
  by normal direction (5° threshold) and plane distance (0.1 unit threshold). Groups exceeding a
  configurable minimum area produce `ArrayOccluder3D` resources parented under a single `Occluders`
  container node. Re-baking is idempotent — previous occluders are replaced, not duplicated.

  **Configuration (LevelRoot exports):**
  - `bake_generate_occluders` (bool, default off): master toggle.
  - `bake_occluder_min_area` (float, default 4.0): minimum coplanar face-group area (world units²)
    to emit an occluder. Smaller surfaces rarely block enough pixels to justify culling overhead.

  **Dock UI:** "Generate Occluders" checkbox and "Min Area" SpinBox in Manage tab → Bake section.
  Settings persist in `.hflevel` save/load and sync bidirectionally with LevelRoot exports.

  **Validation:** `check_occlusion_coverage()` now runs as part of `check_bake_issues()`:
  - Warns when occluder generation is enabled but produced no occluders (surfaces too small).
  - Reports info-level coverage stats (occluder count + estimated % of baked AABB surface).

  13 new tests in `test_occluder_generation.gd`: direct-child meshes, chunked hierarchy
  (`BakedChunk_*` intermediary nodes), coplanar merging, plane separation, min-area filtering,
  idempotent re-generation, postprocess toggle, validation coverage and missing-occluder warnings.

- **I/O-to-Signal runtime bridge** (Apr 2026): Entity I/O connections now automatically translate
  into live Godot signals at bake and export time, eliminating the need for manual runtime wiring.

  New `HFIORuntime` dispatcher node (`hf_io_runtime.gd`, `class_name HFIORuntime`) scans entities
  for `entity_io_outputs` metadata and builds a runtime connection table keyed by node instance ID.
  On output fire, the dispatcher delivers to target entities via a 4-tier resolution cascade:
  1. Direct method call (e.g. `target.Open()`)
  2. Snake-case variant (e.g. `target.turn_on()` for input name `TurnOn`)
  3. Generic handler (`target._on_io_input(input_name, parameter)`)
  4. User signal emission (`io_Open` signal on target)

  Source entities receive `io_<OutputName>` user signals so game scripts can use standard
  `emit_signal("io_OnTrigger", "")` / `connect()` patterns. Delay and fire-once semantics are
  handled automatically. Debug signals `io_fired` and `io_received` emit per-delivery for
  accurate fan-out reporting.

  **Integration points:**
  - `export_playtest_scene()` auto-injects an `HFIODispatcher` child when entities have I/O
    connections — exported scenes are play-ready with no additional setup.
  - New `bake_wire_io` export on LevelRoot (Inspector toggle, default off): when enabled,
    `postprocess_bake()` attaches a dispatcher to the baked container with `extra_scan_roots`
    pointing to the sibling `entities_node`.
  - `HFEntitySystem.fire_output(entity, output_name, parameter)` delegates to the dispatcher
    when present, falls back to direct multi-target resolution otherwise.

  **Robustness:**
  - Connections keyed by node instance ID — duplicate source names are isolated per-instance.
    `fire_from(entity)` dispatches only that entity's connections; `fire("name")` fans out to
    all sources sharing the name.
  - `extra_scan_root_paths: Array[NodePath]` (@export) persists across scene save/reload.
    Transient `extra_scan_roots: Array[Node]` covers live-session bake paths.
  - `wire()` is safe to call repeatedly: `_disconnect_all_signals()` tears down stale lambdas
    before reconnecting; `_prune_overlapping_roots()` deduplicates by instance ID and removes
    descendant roots covered by an ancestor, preventing double-registration.
  - `_find_dispatcher()` walks up to tree root as fallback when `current_scene` is null
    (editor context, GUT tests).

  36 new tests in `test_io_runtime.gd`: wiring, method dispatch (direct/snake-case/generic/signal
  fallback), parameter passing/override, fire-once, user signal creation and emission, multi-target
  fan-out, chain reactions, debug signal accuracy (per-target `io_fired`/`io_received`), missing
  target safety, rewire idempotency (no duplicate handlers), duplicate source isolation
  (`fire_from` vs `fire`), extra scan roots (transient, NodePath, overlap dedup, descendant
  pruning), `fire_on()` static helper, `HFEntitySystem.fire_output()` fallback.
  Total: **1357 tests across 74 files**.

- **Collision chunking for bot navigation** (Apr 2026): Replaced monolithic ConcavePolygonShape3D
  collision with a 3-tier collision mode system for better physics broadphase and navigation mesh
  generation. Configured via `bake_collision_mode` on LevelRoot (Inspector export):
  - **Mode 0** (default): Legacy trimesh — single ConcavePolygonShape3D (backward compatible).
  - **Mode 1**: Per-brush convex hulls — each brush gets a ConvexPolygonShape3D via
    `Baker.build_convex_collision_shapes()`. Supports `bake_convex_clean` (deduplicate vertices,
    default true) and `bake_convex_simplify` (AABB-proportional grid merge, 0.0–1.0).
  - **Mode 2**: Per-visgroup partitioned collision — separate StaticBody3D per visgroup, each
    containing convex hulls for its member brushes. Ungrouped brushes fall into a default body.

  Works across all bake paths: face-material (`bake_from_faces`), CSG single (`bake_single`),
  and CSG chunked (`bake_chunked`). Subtractive brushes are excluded from convex hull generation.
  Real mesh vertices are extracted (not AABB corners) so non-box shapes get accurate collision.
  Visgroup partitioning runs before heightmap collision append to prevent heightmap shape loss.
  Degeneracy guard always runs (vertex dedup for unique count ≥ 4) regardless of `convex_clean`
  setting. Settings persist in `.hflevel` via `capture_hflevel_settings()`/`apply_hflevel_settings()`.

  22 new tests: 11 in `test_baker.gd` (convex shape generation, dedup, simplification, clean
  flag, trimesh default, face bake convex mode, snapshot hull verts) and 11 in `test_bake_system.gd`
  (collision data collection, subtractive filtering, real mesh verts, entity brush skip, 6 async
  integration tests for mode 2 single/chunked/heightmap/trimesh preservation).
  Total: **1321 tests across 73 files**.

## [0.2.0] - 2026-04-09
### Added
- **Map import vertex welding** (Apr 2026): `MapIO.parse_map_text()` now runs a post-parse
  vertex welding pass on all parsed brush face points before constructing brush geometry.
  Near-coincident vertices (within `import_weld_tolerance`, default 0.01 units) are averaged
  to a shared position, closing micro-gaps caused by floating-point representation drift in
  legacy .map editors. Uses BFS over a spatial hash with 27-cell neighbor lookup so pairs
  straddling a snap-grid boundary are never missed. The tolerance is configurable via the
  static `MapIO.import_weld_tolerance` property; set to 0.0 to disable.

- **Non-planar face detection** (Apr 2026): `HFValidationSystem.check_bake_issues()` now
  flags faces with 4+ vertices where any vertex deviates from the face plane beyond
  `planarity_tolerance` (default 0.01 units). Reported as `type: "non_planar"`, severity 1.
  Adjustable per-instance via `val_sys.planarity_tolerance`.

- **Micro-gap detection** (Apr 2026): `check_bake_issues()` now detects near-coincident
  but not-exactly-equal vertices across different brushes that would cause seam tearing
  after bake. Reported as `type: "micro_gap"`, severity 1. Tolerance controlled by
  `val_sys.weld_tolerance` (default 0.001 units).

- **Vertex welding auto-fix** (Apr 2026): `HFValidationSystem.weld_brush_vertices(brush)`
  snaps all vertices within `weld_tolerance` of each other to their averaged position using
  BFS grouping over a 27-cell spatial hash. Calls `ensure_geometry()` on every modified face
  to refresh normals and bounds. Returns the count of welded vertices.

- **Planarity auto-fix** (Apr 2026): `HFValidationSystem.fix_non_planar_faces(brush)`
  projects drifting vertices back onto the best-fit plane defined by each face's first three
  vertices. Calls `ensure_geometry()` after correction. Returns the count of vertices fixed.

- **Configurable validation tolerances** (Apr 2026): `HFValidationSystem` gains two public
  properties — `weld_tolerance` (default 0.001) for vertex coincidence and `planarity_tolerance`
  (default 0.01) for face-plane deviation. These control the new checks and auto-fix methods.
  The `_edge_key()` function used by non-manifold/open-edge detection retains its fixed 0.001
  precision — it is intentionally decoupled from `weld_tolerance` so topology checks remain
  stable regardless of the weld knob setting.

  21 new tests in `test_weld_and_planarity.gd`: non-planar detection (5), vertex welding (3),
  planarity fix (3), micro-gap detection (2), edge-key independence (1), boundary-straddling
  coverage (3), MapIO integration (2), MapIO unit (2).
  Total: **1299 tests across 73 files**.

### Changed
- **Non-blocking face-mode bakes** (Apr 2026): Full bakes using the face-material path
  (`bake_use_face_materials = true`) no longer freeze the editor. The bake system now operates in two
  phases:
  1. **Synchronous snapshot**: captures each brush's triangulated face geometry, resolved materials,
     and world transform into plain data (PackedArrays + Material refs) before any yields. This
     ensures the bake operates on a single coherent scene state regardless of edits during the bake.
  2. **Cooperative yield pass**: iterates the frozen snapshots in batches of 8 brushes, yielding
     `process_frame` between batches so the editor remains responsive. Progress is reported via
     `bake_progress` signals ("Collecting faces N/M").

  `baker.gd` gains four new public methods: `snapshot_brush_faces()` (pre-triangulate + resolve
  materials for one brush), `collect_snapshot_groups()` (world-space transform + grouping from frozen
  data), `collect_brush_face_groups()` (convenience wrapper for sync callers), and
  `build_mesh_from_groups()` (atlas pass + ArrayMesh + collision from pre-collected groups). The
  existing `bake_from_faces()` remains as a thin synchronous wrapper for backward compatibility.

  Bake time estimation (`estimate_bake_time()`) is also corrected: frame-yield idle time is tracked
  via `_yield_overhead_ms` and subtracted from `_last_bake_duration_ms` in both `bake()` and
  `bake_selected()`, so the ms-per-brush ratio reflects actual CPU work rather than wall-clock time
  inflated by editor frame pacing.

  **Note**: Material *resources* referenced in the snapshot are not deep-cloned. If a
  `StandardMaterial3D` property is mutated in-place during the yield window, the baked output will
  reflect the new property value. This is an accepted trade-off — the window is narrow and the
  material identity is correct.

### Fixed
- **Preview node memory leaks during undo/redo** (Apr 2026): Editor preview geometry (drag preview
  brushes, extrude preview brushes, subtract preview wireframes) could leak MeshInstance3D nodes during
  rapid undo/redo cycles. Three fixes:
  1. `plugin.gd` now connects to `EditorUndoRedoManager.version_changed` and force-resets transient
     input modes (DRAG_BASE, DRAG_HEIGHT, EXTRUDE, SURFACE_PAINT) via `HFInputState._force_reset()`,
     which cascades through `_on_input_state_force_reset` to free drag/extrude preview nodes.
     Persistent modes (VERTEX_EDIT) are explicitly excluded — `commit_action()` fires
     `version_changed` after every vertex operation, so resetting it would desynchronize
     `_vertex_mode` in plugin.gd from `input_state.mode`. The transient-mode predicate is extracted
     to `HFInputState.is_transient_preview_mode()` (shared between plugin.gd and tests).
  2. `HFSubtractPreview` gains a `destroy()` method that immediately frees all pooled MeshInstance3D
     nodes and the container Node3D (via `free()`, not `queue_free()`, to prevent orphans during
     tree teardown where the next frame may never arrive).
  3. `level_root.gd _exit_tree()` now calls `subtract_preview.destroy()`,
     `extrude_tool.cancel_extrude()`, and `drag_system._clear_preview()` to clean up all preview
     nodes when the LevelRoot leaves the scene tree.
  8 new tests: 6 in `test_drag_dimensions.gd` (version_changed predicate for all 6 input modes),
  2 in `test_subtract_preview.gd` (destroy with/without prior enable).
  Total: **1278 tests across 73 files**.

### Added
- **Better Terrain Integration — Auto Connectors** (Apr 2026): Auto-generate ramps or stairs between
  height levels during bake. `HFAutoConnector` class (`paint/hf_auto_connector.gd`) scans all paint
  layer pairs, detects cross-layer height boundaries (adjacent cells where one layer's filled cell
  neighbours another layer's filled cell at a different height, threshold ≥0.1 world units), groups
  contiguous boundary edges by direction, and generates connector meshes via the existing
  `HFConnectorTool`. Three modes: **Ramp** (smooth slope), **Stairs** (stepped with configurable step
  height), and **Auto** (picks stairs when height diff ≥ threshold, ramp otherwise). Connector width
  configurable in cells. Deduplication uses canonical 6-part key (both layer indices + both cell coords)
  so corner and T-junction edges are never dropped. Integrated into `HFBakeSystem.postprocess_bake()` —
  connectors generate before navmesh bake so `PARSED_GEOMETRY_STATIC_COLLIDERS` mode picks up connector
  collision shapes. Selection bakes (`bake_selected`) skip auto-connectors to avoid pulling in
  unrelated geometry. 4 new export properties on LevelRoot: `bake_auto_connectors`, `bake_connector_mode`,
  `bake_connector_stair_height`, `bake_connector_width`. Dock UI: "Auto Connectors" checkbox, Mode
  dropdown (Ramp/Stairs/Auto), Step Height and Width spinboxes in Manage tab Bake section. Full state
  persistence in `.hflevel` via `hf_state_system.gd` and dock settings export/import.
  27 tests in `test_auto_connector.gd` + 13 integration tests in `test_bake_system.gd`.
  Total: **1270 tests across 72 files**.
### Fixed
- **NavigationMesh parsed_geometry_type property name** (Apr 2026): `bake_navmesh()` unconditionally
  assigned `nav_mesh.parsed_geometry_type`, which was renamed to `geometry_parsed_geometry_type` in
  Godot 4.6. Every navmesh bake logged `Invalid assignment of property or key 'parsed_geometry_type'`
  and silently failed to set collider-only parse mode. Extracted to version-safe
  `_set_parsed_geometry_type(target, value)` static helper that probes both property names via `in`.
  4 unit tests exercise both branches (new-name, legacy-name via mock, both-names priority, neither-name
  fallback).
- **Merge Tool** (Apr 2026): Combine 2+ selected brushes into a single CUSTOM brush before baking.
  `HFBrushSystem.merge_brushes_by_ids()` collects all faces from source brushes and transforms
  their `local_verts` and normals through the full `Transform3D` pipeline (source local → world →
  merged local) using `affine_inverse()`, so rotated and scaled brushes merge correctly. The merged
  brush inherits the first source brush's full `global_transform` (not just position). Per-brush
  `material_override` is registered into the MaterialManager via `add_material_to_palette()` and
  stamped as `material_idx` on faces that relied on the brush-level override (material_idx == -1),
  so multi-material merges preserve all visual appearances. Metadata (visgroups, group_id,
  brush_entity_class) inherited from first brush. Pre-validation via `can_merge_brushes()` rejects
  < 2 brushes, missing IDs, and mixed operation types (add/subtract). Keybinding: **Ctrl+Shift+M**.
  Context toolbar "Mrg" button, command palette entry, full undo/redo via `HFUndoHelper.commit()`.
  23 tests in `test_merge_tool.gd` covering validation, face combining, full-transform vertex/normal
  rotation, multi-material index separation, same-material dedup, and metadata preservation.
  Total: **1226 tests across 71 files**.
- **Material Atlasing** (Apr 2026): Packs per-face material albedo textures into a single atlas
  to reduce draw calls on baked levels. `HFMaterialAtlas` class (`hf_material_atlas.gd`) with
  shelf bin-packing, gutter padding (2px edge-pixel extension to prevent mipmap bleed), and
  half-texel UV inset (clamped for small tiles so 1px textures never collapse to zero-size rects).
  Baker integration in `bake_from_faces()`: when `use_atlas` is enabled, faces are split per-material
  into tiling vs non-tiling sub-groups — faces with UVs outside [0,1] (e.g. `uv_scale > 1`) are
  excluded from the atlas and rendered as separate surfaces with their original material so hardware
  texture repeat works correctly, while non-tiling faces of the same material are still atlased.
  Dock UI: "Material Atlas" checkbox in Manage tab Bake section (requires Face Materials enabled).
  `bake_use_atlas` property on LevelRoot, persisted in `.hflevel` state via `hf_state_system.gd`,
  synced in dock settings export/import, and wired through `build_bake_options()`.
  26 new tests in `test_material_atlas.gd` covering atlas building, UV remapping, shelf packing,
  gutter fill, small-tile inset clamping, tiling exclusion, per-face tiling split, and full baker
  integration. Total: **1203 tests across 70 files**.
- **Displacement surfaces** (Apr 2026): Source Engine-style displacement surfaces on quad brush faces.
  `HFDisplacementData` resource stores a subdivided grid (power 2-4, producing 5x5 to 17x17 vertices)
  with per-vertex distance offsets along the face normal. `HFDisplacementSystem` subsystem provides
  create/destroy, paint (Raise/Lower/Smooth/Noise/Alpha modes with quadratic falloff), sew adjacent
  displacements along shared edges, elevation scale, and power resampling via bilinear interpolation.
  `FaceData.displacement` property integrates with the existing `triangulate()` → `baker.bake_from_faces()`
  pipeline, generating subdivided grid meshes with per-vertex normals and CW winding. Baker supports
  per-vertex normals for displacement faces. Dock UI includes a collapsible Displacement section in the
  Brush tab with create/destroy, power/elevation spinboxes, paint mode dropdown, radius/strength controls,
  smooth/noise/sew buttons, and sew group spinbox. Plugin handles displacement paint input with raycast
  plane intersection, convex polygon bounds check, and quadratic falloff brush. All operations are fully
  undoable via `_try_undoable_action()` with return-value checking. Continuous paint strokes capture
  pre-state on mouse-down and commit a single undo action on mouse-up. Displacement data serializes
  in `.hflevel` saves via `to_dict()`/`from_dict()`.
- **Edge bevel (chamfer)** (Apr 2026): `HFBevelSystem` subsystem replaces a sharp edge shared by two
  faces with configurable bevel segments (1-16) approximating a rounded profile. Uses slerp arc
  interpolation between face pull-back directions. Generates bevel strip quads, corner cap triangle fans
  at both endpoints, and updates all neighboring faces' shared vertices based on face-normal side
  assignment to maintain manifold topology. Dock UI includes a collapsible Bevel section with segments
  and radius spinboxes. Requires vertex/edge mode (V key) with an edge selected.
- **Face inset** (Apr 2026): `HFBevelSystem.inset_face()` shrinks a face inward by a configurable
  distance and creates connecting side quads between the original boundary and the inset boundary.
  Optional height parameter extrudes the inset face along its normal. Collapse guard rejects inset
  distances that would degenerate the face. Dock UI provides inset distance and height spinboxes.
- **LevelRoot displacement/bevel API** (Apr 2026): 11 delegate methods on LevelRoot for undo system
  compatibility: `create_displacement`, `destroy_displacement`, `set_displacement_elevation`,
  `set_displacement_power`, `set_displacement_sew_group`, `smooth_displacement`, `noise_displacement`,
  `sew_all_displacements`, `paint_displacement`, `bevel_edge`, `inset_face`. All call through to
  subsystems and `tag_brush_dirty()` on success.
- **`_try_undoable_action()` dock helper** (Apr 2026): Generic helper that captures pre-state, calls a
  LevelRoot method, checks the bool return value, and only commits undo + records history on success.
  Used by all displacement/bevel dock callbacks to ensure no false success toasts or empty undo entries.
- 55 new tests across 2 files (`test_displacement.gd` 40, `test_bevel.gd` 15). Total: **1172 tests
  across 69 files**.

### Fixed
- **Dialog/timer lambda capture crashes** (Apr 2026): Six unguarded lambda closures connected to
  `ConfirmationDialog.confirmed/canceled` signals and `SceneTreeTimer.timeout` could fire after the
  owning node (`dock.gd`, `hf_spawn_system.gd`, `hf_prefab_library.gd`) was freed during plugin
  reload or scene transitions, producing "Lambda capture at index 0 was freed" errors. Added
  `is_instance_valid(self)` guards to all six closures: spawn fix dialog confirmed/canceled
  (dock.gd), paint layer rename dialog confirmed (dock.gd), scatter mesh file dialog file_selected
  (dock.gd), debug cleanup timer (hf_spawn_system.gd), and prefab variant/tags dialog confirmed
  (hf_prefab_library.gd).
- **Inside-out face rendering** (Apr 2026): Manually-defined brush faces (`_build_box_faces()`, polygon
  tool, path tool) used CCW vertex winding, which Godot 4's CW front-face convention treated as
  back-facing. Textures appeared on the inside of brushes. Fixed by reversing vertex order to CW in all
  three face generators and swapping the cross-product in `_compute_normal()` (`(c-a).cross(b-a)` instead
  of `(b-a).cross(c-a)`) so `ensure_geometry()` naturally produces outward normals for CW-wound faces.
  Includes `winding_version` serialization field and centroid-based load-time migration in
  `apply_serialized_faces()` so existing `.hflevel` and `.hfprefab` saves render correctly without
  manual intervention.
- **Index rebasing in merged geometry** (Apr 2026): `baker.gd _concat_surface_arrays()` appended
  `ARRAY_INDEX` buffers without rebasing by the running vertex count, corrupting triangles when
  merging indexed surfaces. Also failed when mixing indexed and non-indexed surfaces (first non-indexed
  caused later indexed buffers to be silently dropped). Now synthesizes sequential indices for
  non-indexed surfaces and rebases all subsequent indices by the accumulated vertex count.
- **Convex hull face reconstruction** (Apr 2026): `hf_vertex_system.gd _faces_from_convex_hull()`
  tracked an `assigned` dictionary that prevented hull vertices from appearing in multiple faces.
  Since convex hull vertices belong to 3+ faces (e.g., cube corners), this dropped valid faces and
  produced incomplete shells. Rewritten to track discovered *planes* (by normal+distance dedup)
  instead, allowing vertices to participate in all their coplanar groups.
- **Preview visuals on chunked bakes** (Apr 2026): `hf_bake_system.gd _apply_preview_visuals()` only
  iterated direct children, missing `MeshInstance3D` and `MultiMeshInstance3D` nodes nested under
  `BakedChunk_*` nodes from chunked bakes. Extracted to `_apply_material_recursive()` that walks the
  full subtree.
- **UV spinbox edits not undoable** (Apr 2026): `dock.gd _on_uv_param_changed()` mutated `FaceData`
  directly without going through the undo system. Now routes through `level_root.set_face_uv_params()`
  via `HFUndoHelper.commit()` with a collation tag so rapid spinbox drags merge into one undo step.
- **UV undo history spam** (Apr 2026): `HFUndoHelper.commit()` fired the history callback on every
  collated commit, flooding the history UI with duplicate entries during spinbox drags. Now only fires
  on the first action of a collation run. Collation tracking and history callback logic extracted into
  `_update_collation()` / `_fire_history_cb()` helpers, wired into all three code paths (>5 args,
  null undo_redo, and normal) so suppression works everywhere.
- **bake_unwrap_uv0 not persisted** (Apr 2026): The "Unwrap UV0" toggle was exported on `level_root`
  and used in bake options but missing from `hf_state_system.gd capture_hflevel_settings()` /
  `apply_hflevel_settings()`, silently resetting across state round-trips. Added to both.
- **HFUndoHelper >5 args collation** (Apr 2026): The >5-args early-return path in `undo_helper.gd`
  passed an empty dict `{}` to `_update_collation()`, so `_last_collation_state.is_empty()` was
  always true and subsequent same-tag calls could never collate. Now captures actual state before
  the early return.

### Added
- **Clip to Convex** (Apr 2026): `hf_vertex_system.gd clip_to_convex(brush_id)` computes the convex
  hull of a brush's vertices and rebuilds its faces to match. Each hull face inherits UV settings
  (projection, scale, offset, rotation, material) from the closest original face by normal dot
  product. Available as "Convex" button in vertex edit context toolbar and via the command palette.
- **Smart incremental bake** (Apr 2026): The main Bake button now auto-detects dirty brushes and
  routes to `bake_dirty()` when `_dirty_brush_ids` is non-empty and no full reconcile is needed,
  avoiding unnecessary full re-bakes during iterative editing.
- **Chunk Size control** (Apr 2026): SpinBox in Manage tab Bake section (0-256, default 32) to
  configure `bake_chunk_size` directly from the dock. Synced through toggle/float bindings, root
  state sync, and preset save/load.
- **Bake Visible Only** (Apr 2026): Checkbox in Manage tab Bake section that skips hidden brushes
  during bake. Filtering applied in both `append_brush_list_to_csg()` and
  `_append_face_bake_container()`. Persisted in state system and presets.
- **MultiMesh bake consolidation** (Apr 2026): "Use MultiMesh" checkbox in Manage tab Bake section.
  `_consolidate_to_multimesh()` in `hf_bake_system.gd` post-processes the baked container, grouping
  identical mesh resources and replacing groups of 2+ with `MultiMeshInstance3D` nodes (preserving
  materials). Preview visuals (wireframe/proxy) apply to consolidated MMI nodes.
- **Non-manifold geometry warnings** (Apr 2026): `check_bake_issues()` in `hf_validation_system.gd`
  now analyzes edge adjacency from each brush's `FaceData.local_verts`. Reports open edges
  (shared by 1 face, severity 1) and non-manifold edges (shared by 3+ faces, severity 2).
- **UV projection controls** (Apr 2026): Per-face UV controls in Paint tab — projection dropdown
  (Planar X/Y/Z, Box UV, Cylindrical), scale/offset/rotation spinboxes, and Re-project button.
  Material browser gains "Apply + Re-project (Box UV)" context action.
- **UV0 unwrap during bake** (Apr 2026): Optional "Unwrap UV0" toggle applies per-vertex planar
  projection based on dominant normal axis during bake. Available in Manage tab Bake section.
- **Subtract brush wireframe overlay** (Apr 2026): Subtraction brushes render a red-orange wireframe
  overlay (shared shader across all instances) for visibility in both face-material and fallback
  material paths.
- **Per-surface material preservation in baker** (Apr 2026): `_merge_entries_worker()` groups meshes
  by material and `bake_from_faces()` builds a single ArrayMesh with one surface per material group,
  preserving per-face materials through the bake pipeline.
- **HFUndoHelper 4/5-arg support** (Apr 2026): `undo_helper.gd` `commit()` now handles methods with
  up to 5 arguments (was limited to 3), enabling undo for `set_face_uv_params()` and similar.
- **Face winding migration** (Apr 2026): `to_dict()` now writes `winding_version: 1`. On load,
  `apply_serialized_faces()` detects v0 data and runs `_migrate_face_winding()`, which computes the
  brush centroid and reverses any face whose normal points inward. This correctly handles both old CCW
  manual faces (reversed to CW) and old CW mesh-extracted faces (left unchanged). No manual
  intervention is needed for existing saves.
- 29 new tests: mixed indexed/non-indexed concat (5), recursive preview on chunks (5), UV-history
  collation (8), >5-arg collation (1), baker material preservation (10), winding migration v0→v1 (1),
  winding round-trip v1 (1). Total: **1120 tests across 67 files**.

- **UV transform order corrected** (Apr 2026): `_apply_uv_transform()` in `face_data.gd` previously
  applied rotation after scale+offset (`(uv * scale + offset).rotated(R)`), which rotated the offset
  and caused texture drift when combining rotation with offset. Now applies rotation first
  (`uv.rotated(R) * scale + offset`), matching Valve 220 convention. Includes v0→v1 migration in
  `from_dict()`: uniform-scale faces get offset adjusted; non-uniform-scale+rotated faces are baked
  to `custom_uvs`. `to_dict()` now writes `uv_format_version: 1`.
- **Carve UV preservation** (Apr 2026): `hf_carve_system.gd` carved slice pieces previously lost all
  UV settings from the original brush, defaulting to PLANAR_Z with no offset. `_copy_uv_settings_to_piece()`
  now matches each slice face to the best source face by normal dot product, copies `uv_scale`,
  `uv_offset`, `uv_rotation`, and `material_idx`, sets BOX_UV projection, and compensates the UV
  offset for the positional difference between the original brush center and the slice center so
  textures remain aligned across all surviving faces.
- **Tile justify mode fixed** (Apr 2026): The "tile" UV justify mode in `hf_brush_system.gd` was using
  `1.0 / max(axis)` which fit the larger axis to 1.0 (letterbox behavior). Now uses `1.0 / min(axis)`
  so the shorter axis fills 0..1 and the longer axis tiles past 1.0, preserving aspect ratio.

### Added
- **Stretch and Tile UV justify modes** (Apr 2026): `hf_brush_system.gd` `_justify_face()` now
  supports "stretch" (non-uniform scale to fill 0..1 on both axes) and "tile" (uniform scale so the
  shorter axis fills 0..1, longer axis tiles, centered). Available via context toolbar and dock UI.
- **Rotation texture lock support** (Apr 2026): `face_data.gd` gains `adjust_uvs_for_rotation(angle_rad)`
  which counter-rotates the UV rotation parameter and clears cached UVs. `hf_brush_system.gd` gains
  `_adjust_face_uvs_for_rotation(draft, angle_rad)` wrapper. Ready to wire into future brush rotation
  features (brushes are currently axis-aligned).

- **Signal disconnection leaks in plugin.gd** (Apr 2026): 10 signals connected in `_enter_tree()`
  (context toolbar ×5, hotkey palette ×1, selection filter ×1, dock ×3) were missing corresponding
  disconnections in `_exit_tree()`. This caused duplicate signal handlers after plugin reload cycles,
  leading to repeated action firings and potential crashes.
- **Timer cleanup in level_root.gd** (Apr 2026): Added `_exit_tree()` method to properly stop and
  disconnect `_autosave_timer` and `_reload_timer` signals. Previously, disabling autosave via the
  property setter called `queue_free()` without disconnecting the `timeout` signal first.
- **Extrude tool crash on deleted brush** (Apr 2026): `hf_extrude_tool.gd` now validates
  `is_instance_valid(source_brush)` in `update_extrude()`, `_update_preview()`, and
  `end_extrude_info()`. If the source brush is deleted mid-extrude (e.g., undo), the tool
  gracefully cancels instead of crashing on a freed object reference. `level_root.update_extrude()`
  now detects the self-cancellation and syncs `input_state.end_extrude()` so the HUD and numeric
  input path leave extrude mode cleanly.
- **Input state machine overlapping transitions** (Apr 2026): `input_state.gd` now warns and
  force-resets when `begin_drag()`, `begin_surface_paint()`, `begin_extrude()`, or
  `begin_vertex_edit()` are called from a non-IDLE state. `advance_to_height()` validates it's
  in DRAG_BASE before transitioning. The new `on_force_reset` callback (set by `level_root.gd`)
  tears down active tool implementations (drag preview, extrude preview, vertex selection) before
  mode changes, keeping the state machine and tool objects in sync.
- **Prefab overlay parent null check** (Apr 2026): `hf_prefab_overlay.gd` `hide_overlay()` now
  checks `get_parent()` is not null before calling `remove_child()`, preventing crashes if the
  parent node was freed during plugin unload.
- **Vertex edge array bounds** (Apr 2026): `hf_vertex_system.gd` `split_edge()` now validates
  `edge.size() >= 2` before indexing, preventing out-of-bounds access on malformed input.
- **Duplicate variable declaration in plugin.gd** (Apr 2026): `_on_context_toolbar_action()` had a
  redundant `var root` inside the `"highlight_connected"` match branch that shadowed the function-level
  `root`, causing a parse error. Removed the duplicate.
- **Debug `and true` remnants in dock.gd** (Apr 2026): Four surface paint/UV functions
  (`_on_uv_reset`, `_on_surface_paint_layer_add`, `_on_surface_paint_layer_remove`,
  `_on_surface_paint_texture_selected`) had leftover `and true` in conditions that made the
  conditional check a no-op. Removed all four.
- **Timer closure crash in dock.gd** (Apr 2026): `_on_tutorial_completed()` used a direct method
  reference in `create_timer().timeout.connect(_close_tutorial)`. If the dock was freed before the
  2-second timer fired, the callback would reference a freed object. Wrapped in a lambda with
  `is_instance_valid(self)` guard.
- **Timer nodes leaked in level_root.gd** (Apr 2026): `_exit_tree()` disconnected timer signals but
  never called `queue_free()` on `_autosave_timer` or `_reload_timer`, leaking child Timer nodes.
  Now frees and nulls both.
- **get_parent() null crashes across 8 files** (Apr 2026): `remove_child()` was called via
  `node.get_parent().remove_child(node)` without checking `get_parent()` for null in:
  hf_decal_tool.gd, hf_measure_tool.gd (×2), hf_path_tool.gd, hf_polygon_tool.gd, plugin.gd,
  hf_prefab_system.gd (×2), brush_manager.gd. All now guard with `if node.get_parent():`.
- **Orphan nodes in bulk-clear paths** (Apr 2026): `hf_entity_system.gd clear_entities()`,
  `hf_brush_system.gd clear_brushes()`, and `brush_manager.gd clear_brushes()` called
  `queue_free()` without `remove_child()` first. During state restore, old nodes could still be
  in the tree when new nodes were added. All now call `remove_child()` before `queue_free()`.
- **Division by zero in merge_vertices** (Apr 2026): `hf_vertex_system.gd merge_vertices()` divided
  by `vert_indices.size()` to compute centroid, ignoring that out-of-bounds indices are skipped. If
  all indices were invalid, this was a divide-by-zero. Now tracks `valid_count` and early-returns
  if zero.
- **Edge hover bounds check** (Apr 2026): `hf_vertex_system.gd update_edge_hover()` now validates
  `pick.edge.size() >= 2` before indexing into the edge array.
- **Extrude preview orphan node** (Apr 2026): `hf_extrude_tool.gd _update_preview()` created a
  `_preview_brush` DraftBrush but only added it to the tree if `draft_brushes_node` existed. If
  null, the node leaked. Now `free()`s and nulls it in the else branch.
- **Axis lock return value discarded** (Apr 2026): `hf_drag_system.gd update_drag()` called
  `_apply_axis_lock()` but discarded the return value, making axis lock position clamping a
  silent no-op. Now assigns the result back to `input_state.drag_end`.

### Added
- **Quality-of-Life & Polish** (Apr 2026):
  - **Dark/Light Theme Sync** (`HFThemeUtils`): static utility class detecting dark/light theme via
    `EditorInterface` base color luminance. All custom UI panels (context toolbar, coach marks, hotkey
    palette, operation replay, toasts, selection filter) now use theme-aware colors instead of
    hardcoded values. Each component gains a `refresh_theme_colors()` method called from
    `plugin.gd:_on_editor_theme_changed()`. Toggling Godot's theme instantly updates all HammerForge
    custom panels.
  - **Undo History Browser with Thumbnails** (`HFHistoryBrowser`): replaces the plain ItemList in the
    Manage tab History section. Up to 30 entries with action name, color-coded icon, and viewport
    thumbnail (80x48 captured from `EditorInterface.get_editor_viewport_3d()`). Hover for enlarged
    preview; double-click to navigate undo history to that version. Undo/Redo buttons integrated
    into the browser header.
  - **Measurement Tool Improvements** (`HFMeasureTool`): persistent multi-ruler system (up to 20
    rulers with cycling colors). Shift+Click chains from last endpoint. Angle display between
    consecutive chained rulers at shared vertices. Right-click a ruler to set it as snap reference
    line (projected via `HFSnapSystem.set_custom_snap_line()`). A key toggles align mode. Delete
    removes last ruler; Escape clears all. HUD shows ruler count, distance, alignment status.
  - **Snap System Custom Lines** (`HFSnapSystem`): new `set_custom_snap_line()` /
    `clear_custom_snap_line()` methods. `snap_point()` now considers custom reference lines
    alongside grid/vertex/center candidates.
  - **Performance Monitor Enhancement**: Manage tab Performance section expanded with Entity Count,
    Vertex Estimate, Recommended Chunk Size, and Health summary (green/yellow/red color-coded).
    ProgressBar for brush count (max 200, color-coded). New `level_root` helpers:
    `get_entity_count()`, `get_total_vertex_estimate()`, `get_recommended_chunk_size()`,
    `get_level_health()`.
  - **One-Click Export Playtest Build**: "Export Playtest Build" button in Manage tab Bake section.
    Validates spawn (severity ≥ 2 blocks), bakes, packs baked scene + entities + default lighting as
    temporary `.tscn` at `user://hammerforge_playtest.tscn`, launches via
    `EditorInterface.play_custom_scene()`. Auto-created spawns are fully undoable (state capture
    before spawn creation). New `level_root.export_playtest_scene()` method.
  - 117 new tests across 7 files (theme_utils 15, perf_monitor 5, measure_tool 17, snap_system_custom
    6, history_browser 10, export_playtest 3, dock_history_and_playtest 7 + updates to existing).
    Total: **1091 tests across 62 files**.

- **Terrain & Organic Enhancements** (Apr 2026):
  - **Convert Selection to Heightmap** (`HFBrushToHeightmap`): select brushes → rasterize top faces
    onto a grid → create a sculptable heightmap paint layer. Dock button in Paint tab → Heightmap
    section. Converted layers inherit `base_grid` origin/basis and `chunk_size` from the paint layer
    manager. Emits `paint_layer_changed` and calls `regenerate_paint_layers()` for immediate geometry.
    Supports `grid_snap` as cell size and `height_scale_spin` for height multiplier.
  - **Foliage & Scatter brush** (`HFScatterBrush`): interactive scatter placement with circle and
    spline brush shapes, density/radius/height/slope filtering, scale variation, align-to-normal, and
    deterministic seeding. Preview via MultiMesh (Dots/Wireframe/Full modes). Commit creates permanent
    `MultiMeshInstance3D`. Full dock UI in Paint tab → Foliage & Scatter section with mesh picker,
    density/radius/height/slope/scale spinboxes, shape selector, and Preview/Scatter/Clear buttons.
    Spline mode uses selected node positions as control points with configurable width band.
  - **Path tool extras** (`HFPathTool`): auto-generate stairs (step brushes along sloped segments),
    railings (top rails + posts on both sides with configurable spacing), and trim strips (edge strips
    with material auto-assign) along path tool paths. New `path_extra` enum setting (None/Stairs/
    Railing/Trim) with 8 additional schema parameters. Preview lines: green ticks for stairs,
    yellow for railings, orange for trim.
  - **Dock-level integration tests** (`test_dock_terrain_integration.gd`): 30 tests covering the
    full heightmap convert pipeline (selection → convert → grid inheritance → signal emission →
    regenerate), scatter handler paths (preview circle/spline, commit, clear, stale state cleanup),
    `_build_scatter_settings` UI-to-settings wiring, and `_get_active_paint_layer` lookups.
    Uses a real `LevelRoot` with `auto_spawn_player=false` to avoid bake/playtest orphans.
  - 77 new tests across 4 files (test_brush_to_heightmap 11, test_scatter_brush 14,
    test_path_tool_extras 22, test_dock_terrain_integration 30). Total: **974 tests across 55 files**.

- **Learning & Discovery Aids** (Apr 2026):
  - **Coach marks** (`HFCoachMarks`): first-use floating step-by-step guides for 10 advanced tools
    (Polygon, Path, Carve, Vertex Edit, Extrude, Clip, Hollow, Measure, Decal, Surface Paint).
    Auto-triggered on tool activation. Per-tool "Don't show again" persisted via user prefs.
  - **Operation replay timeline** (`HFOperationReplay`): compact horizontal timeline of up to 20
    recent operations with color-coded icons per action type. Hover for elapsed time, click Replay to
    undo/redo to that point in the history. Toggle with Ctrl+Shift+T. Records undo versions from
    `EditorUndoRedoManager` and drives `UndoRedo.undo()`/`redo()` to reach the target version.
  - **Enhanced command palette** (Ctrl+K): fuzzy search with subsequence matching, word-boundary and
    consecutive-character bonuses. "Did you mean: ..." suggestion when no exact match found. Caps at 5
    fuzzy results. Ctrl+K added as additional toggle shortcut alongside Shift+? and F1.
  - **Example library** (`HFExampleLibrary`): 5 built-in demo levels (Simple Room, Corridor with
    Doorway, Jump Puzzle Platforms, Hollowed Building, Simple Arena) with difficulty badges, tags,
    searchable browser, and "Study This" annotations. Load button clears the scene and instantiates
    brushes + entities from JSON definitions. Section in Manage tab (collapsed by default).
  - `data/example_levels.json`: structured example level data with brush/entity definitions and
    per-level annotations.
  - 63 new tests across 4 files (test_coach_marks 14, test_operation_replay 23, test_fuzzy_search 9,
    test_example_library 17). Total: **944 tests across 54 files**.

- **I/O Connections & Entity Polish** (Apr 2026):
  - **Smart auto-routing**: connection lines now use quadratic Bézier curves with arrowheads instead
    of straight lines. Parallel connections between the same pair of entities offset laterally to
    avoid overlap (0.3 units per route).
  - **Color by type/delay**: output names are mapped to colors (cyan=OnTrigger, red=OnDamage,
    yellow=OnUse, green=OnOpen, magenta=OnBreak, orange=OnTimer, etc.). Fire-once connections pulse
    brighter. Delayed connections dim proportionally.
  - **I/O wiring panel** (`HFIOWiringPanel`): embedded in Entities tab with connection summary,
    outputs list, quick-wire form (output/target dropdown/input/param/delay/once), and preset
    picker with target tag mapping.
  - **Connection presets** (`HFIOPresets`): 6 built-in presets (Door+Light+Sound, Button→Toggle,
    Alarm Sequence, Pickup+Remove, Damage+Break, Timer Lights). Save entity connections as reusable
    user presets. Target tags map to actual entity names at apply time. User presets persist to the
    editor config directory (not the repo).
  - **Highlight Connected**: toggle to pulse-highlight all entities linked to the selected entity.
    SphereMesh overlays with animated alpha. Summary label in context toolbar ("Triggers 2 targets").
  - **Cross-UI highlight sync**: `highlight_connected` is authoritative on the visualizer, pushed
    to context toolbar via state dict and to wiring panel via `_sync_highlight_button()`. Both paths
    use `set_pressed_no_signal()` to avoid signal loops.
  - Context toolbar gains "HL" toggle button and "IOSummary" label in entity section.
  - `level_root.gd` gains `io_presets` subsystem, `set_highlight_connected()`, and
    `get_connection_summary()` delegation methods.
  - 57 new tests across 3 files (test_io_presets 21, test_io_visualizer_enhanced 20,
    test_io_highlight_sync 16). Total: **873 tests across 50 files**.

- **Bake & Quick Play Optimizations** (Apr 2026):
  - **Bake Selected**: bake only the currently selected brushes and merge output into the existing
    baked container (preserving previously baked geometry).
  - **Bake Changed**: bake only brushes flagged dirty since the last successful bake. Dirty tags are
    retained across failed bakes (`_last_bake_success` guard) and accumulate until the next success.
  - **Bake preview modes**: Full / Wireframe / Proxy toggle in Manage tab. Wireframe uses inline
    `ShaderMaterial` with `render_mode wireframe`. Proxy uses unshaded semi-transparent grey.
  - **Bake time estimate**: extrapolated from the last bake duration and brush count ratio. Shown in
    the Manage tab bake section; includes a "Chunking recommended" tip for >500 brushes.
  - **Bake issue detection** (`check_bake_issues()`): degenerate brush (near-zero thickness sev=2,
    oversized sev=1), floating subtract (sev=1), overlapping subtracts (sev=1). Color-coded overlay
    via `user_message` toast.
  - **Play from Camera**: temporarily moves spawn to editor camera position and writes camera yaw to
    `entity_data["angle"]`, bakes, validates, plays, then restores spawn to its original
    position/angle. Full undo/redo support via `_record_spawn_camera_undo()`.
  - **Play Selected Area**: saves cordon state, sets cordon from selection AABB, bakes within that
    region, validates spawn, plays, then restores the original cordon. Cordon is restored on both
    success and error (severity ≥ 2) paths.
  - Both new Quick Play modes share the same severity ≥ 2 blocking, auto-create, and fix-dialog
    patterns as the standard Quick Play path.
  - **Expanded validation** (`HFValidationSystem.check_bake_issues()`): non-convex/degenerate
    brushes, floating detail, overlapping subtracts with structured severity + message dicts.
  - 30 new tests (bake_system additions, bake_issues, quick_play_modes). Total: **807 tests
    across 47 files**.

- **Prefab variants** (Mar 2026): Prefabs can now contain multiple variants (e.g., wooden/metal/ornate
  door styles). Variants are stored alongside the base data in `.hfprefab` files. Cycle through
  variants on a placed instance with **Ctrl+Shift+V** or the **Var▶** context toolbar button.
  Add new variants via right-click → "Add Variant" in the prefab library.
- **Live-linked prefabs** (Mar 2026): "Save Linked" creates prefab instances that maintain a
  connection to the source `.hfprefab` file. Edit one instance and **Push** changes back to the
  source, or **Pull** to propagate the source to all linked instances. Per-instance overrides
  (transforms, sizes) are preserved during propagation.
- **Enhanced prefab browser** (Mar 2026): Searchable prefab library with tag filtering, variant
  count indicators, right-click context menu (Add Variant, Edit Tags, Delete), and "Save Linked"
  button alongside standard save. Tags support comma-separated values and are persisted in the
  `.hfprefab` file format.
- **Quick group-to-prefab** (Mar 2026): **Ctrl+Shift+P** or **Pfb** button in the context toolbar
  saves the current selection as a prefab instantly with an auto-generated name based on contents.
  Available in both brush-selected and entity-selected toolbar contexts.
- **Prefab ghost overlay** (Mar 2026): Hovering a node that belongs to a prefab instance in the
  3D viewport draws a cyan wireframe bounding box around the entire instance. Orange sphere markers
  highlight nodes with per-instance overrides.
- **HFPrefabSystem subsystem** (Mar 2026): New `systems/hf_prefab_system.gd` subsystem manages
  instance registry, variant cycling, override tracking, live-linked propagation, push-to-source,
  and state serialization. Integrates with undo/redo via state capture/restore.
- **Prefab tags** (Mar 2026): `.hfprefab` files now support a `tags` field (array of strings)
  for categorization. Tags are searchable in the library and filterable via a dropdown.
- 24 new tests (variants, tags, system state, overrides, suggestions, overlay). Total: **777 tests
  across 45 files**.

### Fixed
- **Godot 4.6 API compatibility fixes (Mar 2026):**
  - **Dock undo/redo buttons targeted wrong history**: `_on_history_undo()`, `_on_history_redo()`,
    `_update_history_buttons()`, and `_get_undo_version()` all hard-coded
    `EditorUndoRedoManager.GLOBAL_HISTORY`, but HammerForge actions are recorded against the
    scene's history (first do/undo object is the LevelRoot node). Buttons could disable
    incorrectly or no-op. Fixed with `_get_scene_history_id()` /
    `_get_scene_undo_redo()` helpers that resolve the correct history via
    `get_object_history_id(level_root)`.
  - **`EditorUndoRedoManager` has no `undo()`/`redo()`/`has_undo()`/`has_redo()`**: dock
    buttons called these directly on `EditorUndoRedoManager` which doesn't expose them.
    Fixed to call them on the `UndoRedo` object returned by `get_history_undo_redo()`.
  - **`Image.load()` removed in Godot 4**: `hf_heightmap_io.gd` used the Godot 3 instance
    method. Replaced with the static `Image.load_from_file()` (returns `Image` or `null`).
  - **`popup_centered(Vector2(...))` type mismatch**: two dialog popups passed `Vector2` instead
    of `Vector2i`. Fixed in heightmap import and terrain slot texture dialogs.
  - **Gizmo redraw via nonexistent methods**: `brush_gizmo_plugin.gd` tried `set_dirty()` /
    `redraw()` on `EditorNode3DGizmo` which aren't exposed to script. Replaced with
    `gizmo.get_node_3d().update_gizmos()`.
- **Selection filter popup not attached to scene tree (Mar 2026):**
  - `HFSelectionFilter` (`PopupPanel`, a `Window` subclass) was instantiated but never added
    to the tree, so `popup()` silently failed. Now added as a child of
    `EditorInterface.get_base_control()`.
- **Node-only selection filters left stale face context (Mar 2026):**
  - Filters like "Similar Brushes", visgroup, and detail/structural applied node selection
    without clearing `root.face_selection`. The context toolbar kept showing face-mode UI and
    material ops targeted old faces. Fixed: node-only filter results now call
    `_apply_face_selection(root, {})` to clear faces and update the HUD before applying node
    selection.
- **Apply Last Texture only affected first brush (Mar 2026):**
  - `_apply_last_texture()` broke after the first `DraftBrush` in the selection loop. Fixed to
    iterate all selected brushes. Same fix applied to `_on_context_material_apply()`.
- **Selection filters used local-space normals (Mar 2026):**
  - Normal-based face filters (Walls/Floors/Ceilings) and "Select Similar Faces" compared
    `face.normal` in local space. Rotated brushes would be classified incorrectly. Fixed to
    transform normals to world space via `brush.global_transform.basis * face.normal`. Same
    fix applied to `_select_similar_faces()` in `plugin.gd`.
- **Material assignment no longer requires face selection (Mar 2026):**
  - Double-clicking a texture in the material browser, or clicking the Assign button, now
    falls back to **whole-brush assignment** when no individual faces are selected but brushes
    are selected in the viewport. Previously this showed "No faces selected — select faces
    first" even with brushes highlighted.
  - New `resolve_material_assign_action()` pure-decision helper on `dock.gd` encapsulates
    the face-vs-brush fallback logic, shared by `_on_material_assign()`,
    `_on_browser_material_double_clicked()`, and available for future callers.
- **Texture reimport no longer clears brush selection (Mar 2026):**
  - Loading prototype SVG textures in the material browser could trigger Godot's texture
    reimport pipeline, which emitted spurious empty `selection_changed` signals that cleared
    the dock's brush selection cache.
  - Added `should_suppress_empty_selection()` static guard in `plugin.gd`: ignores empty
    editor selection events when `hf_selection` is still populated. Intentional deselects
    (Escape key, delete, dock Clear Selection button, Commit Cuts) clear `hf_selection`
    first so the guard lets them through.
  - New `selection_clear_requested` signal on `dock.gd` lets the dock tell the plugin to
    clear its cache before calling `editor_selection.clear()`.
  - Reordered `hf_selection.clear()` before `selection.clear()` in three plugin deselect
    paths (Escape, delete brushes, duplicate brushes) for consistency with the guard.
- **Prefab system stability fixes (Apr 2026):**
  - **Inferred-type compilation errors**: GDScript `:=` on untyped `root` parameter returns
    caused Godot 4.6 parse failures in `plugin.gd` and `hf_prefab_overlay.gd`. Changed to
    explicit typed declarations (`var x: Type = ...`).
  - **Undo/redo lost prefab node tags**: `restore_state()` rebuilt the `_instances` registry
    but never re-tagged scene nodes with `hf_prefab_instance`/`hf_prefab_source`/
    `hf_prefab_variant` meta. Prefab overlay and toolbar badge stopped working after undo.
    Fixed by calling `_tag_nodes(rec)` in the restore loop.
  - **Entity identity collisions**: Prefab instance entity membership was tracked by scene
    node name, which can collide across unrelated entities. Replaced with stable UIDs
    (`hf_prefab_entity_id` meta) assigned at registration time. `hf_prefab.gd` `instantiate()`
    now returns `entity_nodes` (Node3D refs) alongside `entity_names`.
  - **Permanent prefab buttons in context toolbar**: Var▶/Push/Pull buttons were permanently
    appended to toolbar sections on first prefab selection and never removed. Rebuilt as
    named child nodes created at build time, toggled visible/hidden in `_apply_context()`
    based on whether a prefab instance is currently selected.
  - **Vertex system API mismatch**: Context toolbar and hotkey palette dispatchers called
    nonexistent `set_sub_mode()`, `merge_selected()`, and `split_selected_edge()` on
    `HFVertexSystem`. Fixed to use `sub_mode` property assignment and new
    `_vertex_merge_selected()` / `_vertex_split_selected_edge()` helpers that resolve
    selection state before calling `merge_vertices()` / `split_edge()`.
  - **Orphan warnings in prefab tests**: `queue_free()` defers deletion past GUT's per-test
    orphan counter. Changed to immediate `free()` in test cleanup.

### Added
- **Improved Selection & Multi-Select (Mar 2026):**
  - **Marquee / box selection**: click-and-drag in Select mode to rubber-band select brushes
    and entities. In Face Select mode, marquee selects individual faces across multiple brushes.
    Semi-transparent blue overlay rectangle drawn during drag. Uses `_select_nodes_in_rect()` for
    brushes/entities and new `_select_faces_in_rect()` for face mode.
  - **Selection filter popover** (`ui/hf_selection_filter.gd`): popup panel with bulk selection
    tools organized by category:
    - **By Normal**: Walls (|Y| < 0.3), Floors (Y > 0.7), Ceilings (Y < -0.7).
    - **By Material**: select all faces matching the currently selected face's material.
    - **Select Similar**: Similar Faces (material + normal within 15°), Similar Brushes (size
      within 20% tolerance, orientation-agnostic).
    - **By Visgroup**: dynamic buttons for each visgroup (auto-rebuilt on open).
    - **By Type**: Detail Brushes (func_detail), Structural (worldspawn).
    Emits `filter_applied(nodes, faces)` signal handled by plugin to apply selection.
  - **"Select Similar" hotkey** (Shift+S): quick-invoke from viewport. Selects faces with
    matching material + normal when faces are selected, or brushes with similar size when
    brushes are selected.
  - **"Apply Last Texture" hotkey** (Shift+T): applies the last texture picked with the
    Texture Picker (T) to the current face or brush selection. Stores `_last_picked_material_index`
    when T picks a material.
  - **"Selection Filters" hotkey** (Shift+F): opens the selection filter popover at mouse position.
  - **Enhanced selection count badge**: status bar now shows combined counts when applicable
    (e.g. "Sel: 3 brushes, 5 faces").
  - **Context toolbar updates**: face section gains "Sim" (Select Similar) and "Last" (Apply
    Last Texture) buttons; brush section gains "Sim" and "Flt" (Selection Filters) buttons.
    Labels now show "N brush(es) selected", "N faces on M brush(es)", "N entities selected".
  - **Command palette updates**: `select_similar`, `apply_last_texture`, and `selection_filter`
    actions added with live gray-out rules.
  - **3 new keymap bindings** in "Tools" and "Selection" categories with human-readable labels.
  - **18 new GUT tests** (`test_selection_features.gd`): keymap binding matches, labels,
    categories, display strings, toolbar label content, `_size_similar()` helper logic.
    **Total: 753 tests across 44 files.**
- **Smart Contextual Toolbar + Command Palette (Mar 2026):**
  - **Floating context toolbar** (`ui/hf_context_toolbar.gd`): appears in the 3D viewport overlay with
    context-sensitive actions based on current selection and tool state. Automatically shows/hides as
    context changes — no manual tab switching needed.
  - **Brush selected** → Extrude Up/Down, Hollow, Clip, Carve, Duplicate, Delete buttons. Label shows
    "N brush(es)" count.
  - **Face selected** → Material thumbnail strip (5 favorites), UV Justify buttons (Fit/Center/L/R/T/B),
    "Apply to Whole Brush" button. Label shows "N face(s)" count.
  - **Entity selected** → I/O connect and Properties quick-edit buttons (jump to Entities tab),
    Duplicate, Delete.
  - **Draw idle** → Quick shape selector (Box/Cyl/Sph/Cone), Add/Subtract toggle with color-coded label
    (green Add / red Sub) and one-click switch.
  - **Dragging** → Live dimension display, Axis Lock buttons (X/Y/Z), Cancel button.
  - **Vertex edit** → Vertex/Edge sub-mode toggle, Merge, Split, Exit buttons.
  - **Auto-mode hint bar**: during brush drawing, a blue overlay bar appears with the current operation
    mode ("Drawing in Add mode — press Subtract to toggle") and a one-click "Switch to Subtract/Add"
    button. Fades in smoothly, auto-hides when not drawing.
  - **Command palette** (`ui/hf_hotkey_palette.gd`): searchable action palette toggled with `Shift+?`
    or `F1`. Lists all HammerForge actions grouped by category (Tools, Editing, Paint, Axis Lock) with
    key bindings. Live search filters by action name or binding. **Live gray-out**: actions that cannot
    run in the current state are visually disabled (e.g. Hollow grayed out with no brush selection,
    paint tools grayed out outside paint mode, vertex tools grayed outside vertex mode). Press Enter to
    execute the first visible+enabled match. Esc to close.
  - **Dock integration**: `dock.gd` gains `_apply_material_to_whole_brush()` and
    `_on_face_assign_material()` convenience methods for toolbar-initiated material assignment.
  - **Plugin integration** (`plugin.gd`): context toolbar and palette added to
    `CONTAINER_SPATIAL_EDITOR_MENU` alongside existing HUD. State updates every frame via
    `_update_context_toolbar_state()` which computes brush/entity/face counts, input mode, operation,
    and vertex state. Action dispatch routes to existing dock/plugin methods (hollow, clip, carve,
    justify, axis lock, tool switch, etc.) with full undo/redo support.
  - **32 new GUT tests** (`test_context_toolbar.gd` 20 tests, `test_hotkey_palette.gd` 12 tests):
    context determination, label content, action signals, material thumbnails, search filtering,
    gray-out logic, toggle visibility. **Total: 726 tests across 43 files.**
- **Player Spawn System + Quick Play Overhaul (Mar 2026):**
  - **New subsystem** (`systems/hf_spawn_system.gd`): `HFSpawnSystem` manages spawn lookup, physics-
    based validation, auto-fix, default spawn creation, and debug visualisation. Follows the
    coordinator+subsystem pattern (RefCounted, injected LevelRoot reference).
  - **Spawn validation** before every Quick Play: floor raycast (PhysicsDirectSpaceState3D), capsule
    collision check (player-sized CapsuleShape3D), ceiling/headroom check, and below-map heuristic.
    Returns structured result with issues list, severity (NONE/WARNING/ERROR), and suggested fix
    position. Runs in < 5 ms via direct space queries.
  - **Auto-fix dialog**: when spawn has critical issues (inside geometry, floating), a
    ConfirmationDialog offers "Fix & Play" (snaps to suggested position) or "Cancel". Warnings
    show a toast but proceed automatically.
  - **Auto-create fallback spawn**: if no `player_start` entity exists, Quick Play auto-creates one
    at the centroid of all brushes + safe height offset, with a warning toast.
  - **Debug visualisation** (`show_validation_debug()`): green/red capsule preview at spawn
    position, floor ray (ImmediateMesh line to hit point or red ray to void), ceiling ray (yellow),
    floor disc marker, red collision sphere for penetration issues. Auto-cleans after configurable
    duration or stays persistent (duration=0) for the "Preview Spawn Debug" toggle.
  - **Manage tab → Spawn section**: "Validate Spawn" button (runs validation + shows debug for 10s),
    "Create Default Spawn" button (creates fallback player_start), "Preview Spawn Debug" checkbox
    (persistent visualisation toggle).
  - **player_start entity enhanced** (`entities.json`): three new properties — `primary` (bool,
    preferred spawn for Quick Play), `angle` (float, yaw rotation in degrees), `height_offset`
    (float, extra height above floor). Color changed from green to cyan. Auto-generated property
    form in Entities dock via existing `hf_entity_def.gd` loader.
  - **Playtest FPS controller** (`playtest_fps.gd`): new `player_start_position` and
    `player_start_rotation_y` exports. `_ready()` applies spawn position/rotation if set.
  - **level_root.gd**: `spawn_system` subsystem initialised in `_ready()`. `_start_playtest()`
    rewritten to use `spawn_system.get_active_spawn()` with primary-flag priority, yaw rotation
    from `angle` property, and legacy fallback scan.
  - **Quick Play tooltip**: dynamically shows active spawn name and position.
  - **21 new GUT tests** (`tests/test_spawn_system.gd`): spawn lookup (no spawns, single, primary
    priority, first fallback, non-player_start filtering), validation (null, not-in-tree, no-physics),
    auto-fix (applies suggested position, null safety), default creation (empty level, brush
    centroid), debug viz (create/cleanup, floor hit, issues, null safety), entity property helpers,
    severity ordering. **Total: 685 tests across 41 files.**
- **Visual Texture Browser + Texture Picker (Mar 2026):**
  - **Visual material browser** (`ui/hf_material_browser.gd`): replaces the text-only material
    ItemList with a scrollable thumbnail grid (64px cells, 5 columns). Each cell shows the actual
    SVG texture preview via `TextureRect`, with a short label and tooltip. Click to select, right-click
    for context menu (Apply to Faces, Apply to Whole Brush, Toggle Favorite, Copy Name).
  - **Search and filters**: live text search bar, pattern dropdown filter (15 patterns + "All"),
    color swatch row (10 clickable color buttons + "All"), and view toggle (Prototypes / Palette /
    Favorites). Filters combine — e.g. pattern=brick + color=red + search="dark" all narrow together.
  - **Favorites system**: right-click any thumbnail to toggle favorite. Favorites view shows only
    starred materials. Favorite state persists in the browser instance.
  - **Hover preview**: hovering a thumbnail in the browser temporarily applies that material to all
    currently selected faces in the viewport. Material reverts on mouse leave.
  - **Texture Picker tool** (T key): eyedropper that raycasts to the face under the cursor, reads
    its `material_idx` from `FaceData`, and sets it as the current selection in the browser. Registered
    in `HFKeymap` under the "Tools" category with display label "Texture Picker".
  - **Context menu**: `PopupMenu` with "Apply to Selected Faces" (uses existing
    `assign_material_to_selected_faces` state action), "Apply to Whole Brush" (iterates selected
    brushes), "Toggle Favorite", and "Copy Name" (clipboard).
  - **Drag-and-drop support**: thumbnails emit drag data `{"type": "hammerforge_material", "index": N}`
    with a thumbnail + label drag preview, following the existing entity/brush preset pattern.
  - **"Load Prototypes" renamed to "Refresh Prototypes"** for clarity (behavior unchanged).
  - **Status bar**: shows "X of Y materials" with filter state, or guidance text when palette is empty.
  - **Backwards compatibility**: hidden legacy `ItemList` preserved for `_refresh_materials_list()`
    sync path; browser rebuilds via new `_refresh_material_browser()` called alongside it.
- **Vertex Editing Enhancements + Polygon Tool + Path Tool (Mar 2026):**
  - **Edge sub-mode for vertex editing** (`systems/hf_vertex_system.gd`): new `VertexSubMode` enum
    (VERTEX, EDGE) toggled with `E` key. Edge selection, additive/toggle selection, wireframe overlay
    (dim gray default, orange selected, yellow hovered). `get_brush_edges()` extracts unique undirected
    edges from face data with canonical deduplication. `pick_edge()` projects edges to screen space for
    click selection. Edge selection syncs to vertex selection so `move_vertices()` works transparently.
  - **Edge splitting** (`Ctrl+E`): `split_edge()` inserts midpoint vertex into every face containing
    the edge, updating `local_verts` and calling `ensure_geometry()`. Mathematically guaranteed to
    preserve convexity on convex hulls. Face snapshot undo via `get_pre_op_snapshots()`.
  - **Vertex merging** (`Ctrl+W`): `merge_vertices()` computes centroid of selected vertices, replaces
    all occurrences in all faces, removes degenerate faces (< 3 unique verts). Validates convexity;
    reverts via face snapshots if invalid.
  - **Edge wireframe overlay** in `plugin.gd :: _update_vertex_overlay`: ImmediateMesh `PRIMITIVE_LINES`
    pass draws all brush edges with color-coded selection/hover state before vertex crosses.
  - **`get_single_selected_edge()`**: returns `[brush_id, edge]` when exactly one edge is selected,
    empty array otherwise. Used by split_edge input handler.
  - **`get_all_edge_world_positions()`**: returns `[{a, b, selected, hovered}]` for overlay rendering.
  - **Static `_point_to_segment_dist_2d()`**: 2D point-to-segment distance for edge picking.
  - **Polygon tool** (`hf_polygon_tool.gd`): `HFPolygonTool` extends `HFEditorTool` (tool_id=102,
    KEY_P). Three-phase state machine: IDLE → PLACING_VERTS → SETTING_HEIGHT. Click to place convex
    polygon vertices on ground plane (grid-snapped), auto-close when clicking near first point (threshold
    configurable via `auto_close_threshold` setting), or Enter to close manually. Mouse drag sets
    extrusion height. Convexity enforced via 2D cross product on XZ plane (`_is_convex_xz()` static
    method). Face data construction: top (CCW winding), bottom (CW), N side quads, all in local space
    relative to AABB center. Winding detection via shoelace formula. ImmediateMesh preview (cyan outline,
    green vertical edges during height stage). Creates brush via `create_brush_from_info()` with undo/redo.
  - **Path tool** (`hf_path_tool.gd`): `HFPathTool` extends `HFEditorTool` (tool_id=103,
    KEY_SEMICOLON). Two-phase state machine: IDLE → PLACING_WAYPOINTS. Click to place waypoints on
    ground plane, Enter to finalize (requires 2+). For each consecutive waypoint pair, builds an
    oriented-box brush (8 corners from direction + perpendicular vectors, 6 FaceData quads). Miter joint
    brushes fill triangular gaps at interior waypoints (angular sorting for convex hull, skipped if angle
    too straight or too acute). All brushes share a `group_id` for auto-grouping. Settings:
    `path_width` (4.0), `path_height` (4.0), `miter_joints` (bool, true). ImmediateMesh preview (cyan
    polyline, parallel width offset lines, perpendicular ticks). Single undo action for entire path.
  - **New keymap bindings** (`hf_keymap.gd`): `vertex_edge_mode` (E), `vertex_merge` (Ctrl+W),
    `vertex_split_edge` (Ctrl+E). Added to "Tools" category with display labels.
  - **Shortcut HUD update** (`shortcut_hud.gd`): vertex edit hints now include "E: Toggle edge mode"
    and "Ctrl+W: Merge verts | Ctrl+E: Split edge".
  - **Tool registry update** (`hf_tool_registry.gd`): `activate_tool()` now accepts optional
    `EditorUndoRedoManager` parameter, passed to tools that create brushes.
  - **Base tool update** (`hf_editor_tool.gd`): added `var undo_redo: EditorUndoRedoManager` member
    for tools that create brushes (polygon, path).
  - **GUT tests**: 3 new test files — `test_vertex_edges.gd` (19 tests: edge extraction, dedup,
    selection, world positions, split, merge, sub-mode, point-to-segment), `test_polygon_tool.gd`
    (16 tests: convexity validation, face construction, normals, empty/degenerate, tool metadata),
    `test_path_tool.gd` (15 tests: segment brush construction, miter joints, face validation,
    tool metadata). Total: **622 tests** across **38 files**.
- **UX Feature Wave — Tutorial, Hints, Subtract Preview, Prefabs (Mar 2026):**
  - **Dynamic contextual hints** (`shortcut_hud.gd`): viewport overlay hints appear when switching
    tool modes (draw, select, extrude, paint). Each hint shows instructional text specific to the
    current mode (e.g. "Click to place corner → drag to set size → release for height"). Auto-fades
    after 4 seconds via tween. Per-hint dismissal persists in user preferences via
    `is_hint_dismissed()` / `dismiss_hint()` on `hf_user_prefs.gd`. `MODE_HINTS` const dictionary
    maps mode keys to hint strings.
  - **Searchable shortcut dialog** (`ui/hf_shortcut_dialog.gd`): replaces the static shortcuts
    popup. Extends `AcceptDialog` with a search `LineEdit` and categorized `Tree`. Categories
    (Tools, Editing, Paint, Axis Lock) populated from `HFKeymap.get_category()` and
    `get_action_label()`. Real-time case-insensitive filtering on action name or key binding string.
  - **Interactive tutorial wizard** (`ui/hf_tutorial_wizard.gd`): 5-step guided first-run experience
    replacing the static welcome panel. Steps: Draw room (`brush_added` signal) → Subtract window
    (`brush_added` + operation validation) → Paint floor (`paint_layer_changed`) → Place entity
    (`entity_added`) → Bake & preview (`bake_finished`). Each step listens for the corresponding
    LevelRoot signal. Optional validation (e.g. `_validate_subtract` checks `operation ==
    SUBTRACTION`). ProgressBar shows step N of 5. Skip Step / Dismiss buttons. Progress persisted
    via `tutorial_step` in user prefs. Dock `highlight_tab()` flashes the relevant tab on each step.
  - **Real-time subtract preview** (`systems/hf_subtract_preview.gd`): wireframe AABB intersection
    overlays between additive and subtractive brushes. Uses ImmediateMesh `PRIMITIVE_LINES` (same
    12-edge box pattern as cordon wireframe). Red material `Color(1.0, 0.3, 0.3, 0.7)`, unshaded,
    no depth test. Debounced rebuild (0.15s), MeshInstance3D pool (max 50), automatic update on
    `brush_added` / `brush_removed` / `brush_changed` signals. Toggle via `show_subtract_preview`
    export on LevelRoot (persisted in state settings). Checkbox in Manage tab → Settings.
  - **Prefab system** (`hf_prefab.gd` + `ui/hf_prefab_library.gd`): save and load reusable brush +
    entity groups as `.hfprefab` JSON files. `HFPrefab.capture_from_selection()` computes centroid
    and stores transforms relative to it. `instantiate()` assigns new brush IDs, offsets transforms,
    and remaps entity I/O connections via name map. Uses `begin_signal_batch()` /
    `end_signal_batch()` for atomic multi-brush creation. `HFPrefabLibrary` dock section in Manage
    tab shows `.hfprefab` files from `res://prefabs/` with drag-and-drop support. Plugin handles
    `"hammerforge_prefab"` drop type with raycast + snap + undo/redo.
  - **New public API methods**: `HFBrushSystem.next_brush_id()` (public wrapper),
    `HFEntitySystem.remap_io_connections()` (remap I/O targets on prefab instantiate),
    `HFKeymap.get_all_bindings()`, `HFKeymap.get_category()`, `HFKeymap.get_action_label()`.
  - **GUT tests**: 4 new test files — `test_shortcut_dialog.gd` (8), `test_tutorial_wizard.gd` (7),
    `test_subtract_preview.gd` (8), `test_prefab.gd` (11). Plus 3 additions to
    `test_user_prefs.gd`. Total: **568 tests** across **34 files**.
- **Usability & Feature Upgrade (Mar 2026):**
  - **Bake failure toast notifications**: `warn_bake_failure()` now emits contextual error messages
    via `user_message` signal (e.g. "No draft brushes found", "You have N pending cuts — try
    'Commit Cuts' before baking", "CSG produced no geometry — check brush operations"). Null baker
    guard also toasts.
  - **Silent failure logging in paint system**: ~20 guard clauses across `hf_paint_system.gd`,
    `hf_paint_tool.gd` now emit `push_warning()` for internal logging and `user_message` for
    user-facing failures (heightmap import failure, paint input ignored, bucket fill limit hit).
  - **Entity definition load error reporting**: `hf_entity_def.gd` now emits `push_error()` on JSON
    parse failure, `push_warning()` for malformed entries and fallback to built-in defaults.
  - **Paint layer rename**: new `display_name` field on `HFPaintLayer` with `rename_layer()` on
    `HFPaintLayerManager`. Dock shows "R" rename button with dialog. Display names serialize in
    `.hflevel` and fall back to layer ID when empty. Backward compatible.
  - **Axis lock visual indicator**: dock shows X/Y/Z toggle buttons with color-coded pressed states
    (red=X, green=Y, blue=Z). Bidirectional sync with keyboard axis lock via
    `set_pressed_no_signal()`.
  - **Entity I/O viewport visualization**: `HFIOVisualizer` (`systems/hf_io_visualizer.gd`) draws
    ImmediateMesh lines between connected entities. Color-coded: green=standard, orange=fire_once,
    yellow=selected entity connections. Throttled refresh (10 frames). Toggle in Entities tab.
  - **Measurement/ruler tool**: `HFMeasureTool` (`hf_measure_tool.gd`) extends `HFEditorTool`
    (tool_id=100, M key). Click point A → click point B → persistent line + Label3D with distance
    and dX/dY/dZ decomposition. Grid-snapped. Escape clears.
  - **Terrain sculpting brushes**: 4 new stroke tools — SCULPT_RAISE, SCULPT_LOWER, SCULPT_SMOOTH,
    SCULPT_FLATTEN (HFStroke.Tool values 6-9). Operates directly on heightmap Image pixels with
    configurable strength, radius, and falloff curve. Dock shows 4 toggle buttons + 3 spinboxes.
    Flatten captures height on first click and lerps toward it.
  - **Dock decomposition into tab builders**: extracted ~2,000 lines from `dock.gd` into 4 builder
    files: `ui/paint_tab_builder.gd`, `ui/entity_tab_builder.gd`, `ui/manage_tab_builder.gd`,
    `ui/selection_tools_builder.gd`. Each is RefCounted, receives dock reference, has `build()` and
    `connect_signals()` methods. `dock.gd` reduced by ~35%.
  - **Baker test coverage**: new `tests/test_bake_system.gd` with 18 tests covering
    `build_bake_options()`, `_is_structural_brush()`, `_is_trigger_brush()`, `count_brushes_in()`,
    `chunk_coord()`, `bake_dry_run()`, `warn_bake_failure()`, and structural filtering.
  - **Carve tool**: `HFCarveSystem` (`systems/hf_carve_system.gd`) — boolean-subtract one brush from
    all intersecting brushes. Progressive-remainder algorithm produces up to 6 box slices per target.
    Preserves material, operation, visgroups, group_id, brush_entity_class. Ctrl+Shift+R shortcut.
    Undo/redo via `HFUndoHelper`.
  - **Decal/overlay system**: `HFDecalTool` (`hf_decal_tool.gd`) extends `HFEditorTool`
    (tool_id=101, N key). Raycast placement of Godot `Decal` nodes oriented to surface normal. Live
    preview follows cursor. Declarative settings: texture path, size, fade. Tagged with `hf_decal`
    meta for serialization.
  - **Integration test suite**: new `tests/test_integration.gd` with 22 end-to-end tests across 8
    categories: brush lifecycle, paint + heightmap, entity workflow, visgroup cross-system, snap
    system, bake cross-system, entity I/O cleanup, and brush info round-trip.
  - **GUT tests**: 99 new tests across 3 files. Total: **512 tests** across **30 files**.
- **FreeCAD-Inspired Improvements (Mar 2026):**
  - **Operation result reporting** (`hf_op_result.gd`): `HFOpResult` lightweight result class returned
    by `hollow_brush_by_id()`, `clip_brush_by_id()`, and `delete_brush_by_id()`. Carries `ok`, `message`,
    and `fix_hint` fields. Failed operations now surface actionable toast notifications (e.g. "Wall
    thickness 6 is too large for brush (smallest dim 10) — Use a thickness less than 5") instead of
    silently returning. `_op_fail()` helper emits `user_message` signal at WARNING level automatically.
  - **Geometry-aware snap system** (`hf_snap_system.gd`): centralized `HFSnapSystem` with three snap
    modes — **Grid** (existing behavior), **Vertex** (8 box corners of all brushes), and **Center**
    (brush centers). Closest geometry candidate within threshold beats grid snap. `_snap_point()` in
    `level_root.gd` now delegates to the snap system. Dock shows G/V/C toggle buttons below the grid
    snap row. Replaces the previous grid-only snapping.
  - **Live dimensions during drag**: `input_state.gd` gains `get_drag_dimensions()` and
    `format_dimensions()`. The mode indicator banner now shows real-time brush dimensions during
    DRAG_BASE and DRAG_HEIGHT gestures (e.g. "Step 1/2: Draw base — 64 x 32 x 48",
    "Step 2/2: Set height — 64 x 96 x 48").
  - **Reference cleanup on deletion**: `delete_brush()` now calls `_cleanup_brush_references()` which
    strips group membership (auto-cleans empty groups), clears visgroup meta, and warns via toast when
    entity I/O connections targeting the deleted node are removed. New
    `cleanup_dangling_connections(deleted_name)` on `HFEntitySystem` removes all I/O connections
    targeting a deleted node and returns the removal count. Exposed on LevelRoot as a delegate.
  - **GUT tests** for new systems: `test_op_result.gd` (15), `test_snap_system.gd` (12),
    `test_drag_dimensions.gd` (8), `test_reference_cleanup.gd` (9) = 44 new tests.
    Total: 413 tests across 27 files.
- **UX Intuitiveness Overhaul (Mar 2026):**
  - **Mode indicator banner**: colored banner between toolbar and tabs shows current tool, gesture
    stage ("Step 1/2: Draw base"), and numeric input. Color-coded per tool: Draw (blue), Select
    (green), Extrude Up (green), Extrude Down (red), Paint (orange). Replaces ambiguous footer text.
  - **Toast notification system** (`ui/hf_toast.gd`): transient notifications surface errors and
    confirmations in the dock. Levels: INFO, WARNING, ERROR with color-coded backgrounds and
    auto-fade. Connected to save/load/export/bake results and new `user_message` signal on
    LevelRoot. Replaces silent `push_error`/`push_warning` calls for user-facing operations.
  - **Readable toolbar labels**: toolbar buttons now show icon + text label (Draw, Select, Add,
    Sub, Paint, Ext Up, Ext Dn) instead of blanking text when icons load.
  - **Inline disabled hints**: "Select a brush to use these tools" text in Selection Tools section
    and "Enable Face Select Mode and click a face to edit" in Materials section. Visible without
    hovering, toggles based on selection/face state.
  - **First-run welcome panel** (`ui/hf_welcome_panel.gd`): 5-step quick-start guide shown on
    first launch. "Don't show again" checkbox persists via user preferences.
  - **Context-sensitive next action hints**: per-tab hint labels at the bottom of each dock tab
    guide users through the workflow (e.g. "Click and drag in the viewport to draw your first
    brush", "Try: Hollow, Clip, or Extrude"). Updates based on scene state.
  - **Shortcuts quick-reference popup**: "?" button on toolbar opens a popup listing all keybindings
    grouped by context (Tools, Editing, Paint, Axis Lock) plus drag/extrude tips. Built dynamically
    from keymap data.
  - **Face hover highlight for extrude**: in extrude mode, hovering over a brush face shows a
    semi-transparent overlay (green for up, red for down) previewing which face will be selected.
    Uses StandardMaterial3D with alpha transparency for filled overlay.
  - **Clear selection button**: small "x" button appears next to "Sel: N brushes" in the footer
    when selection is non-empty. Provides a visible deselect action beyond the Escape key.
  - **`user_message` signal** on LevelRoot: subsystems can surface messages to the dock toast
    system via `root.user_message.emit(text, level)`.
  - `show_welcome` and `hints_dismissed` added to user preferences defaults.
- **Built-in prototype textures (Mar 2026):**
  - **150 SVG prototype textures** (15 patterns x 10 colors) ship with the plugin at
    `addons/hammerforge/textures/prototypes/`. Patterns include solid, brick, checker, cross,
    diamond, dots, hex, stripes (diagonal/horizontal), triangles, zigzag, and directional arrows.
  - **"Load Prototypes" button** in Paint tab → Materials section: one-click batch-load of all 150
    textures as `StandardMaterial3D` resources into the material palette.
  - **`HFPrototypeTextures` catalog class** (`hf_prototype_textures.gd`): static API for querying
    patterns/colors, loading individual textures, creating materials, and batch-populating a
    `MaterialManager`. Uses hardcoded arrays for headless-test compatibility.
  - **HTML preview page** (`docs/prototype_textures_preview.html`): self-contained browser-viewable
    catalog of all 150 textures with search and filtering.
  - **Documentation** (`docs/HammerForge_Prototype_Textures.md`): patterns/colors reference, UI and
    GDScript usage, API reference.
  - **GUT tests** (`tests/test_prototype_textures.gd`): 27 test cases covering catalog constants,
    path generation, resource loading, material persistence (resource_path), and batch loading.
- **Dock UX improvements (Mar 2026):**
  - **Selection Tools section** in Brush tab: hollow, clip, move floor/ceiling, tie entity, and
    duplicator controls now appear contextually when brushes are selected (moved from Manage tab).
  - **Collapsible section polish**: each section now has an HSeparator divider and 4px left-indented
    content for visual hierarchy. Collapsed state persists across sessions via user preferences.
  - **Signal-driven paint/material/face sync**: paint layer, material palette, surface paint, and
    face selection updates are now instant via `paint_layer_changed`, `material_list_changed`,
    `face_selection_changed`, and `selection_changed` signals (replaced 10-frame polling throttle).
  - **`material_list_changed` signal** on LevelRoot: emitted on material add/remove for instant
    dock sync.
  - **`face_selection_changed` signal** on LevelRoot: emitted from `select_face_at_screen()`,
    `toggle_face_selection()`, and `clear_face_selection()` (only when selection actually changes).
    Drives UV/surface paint panel sync and disabled-hint updates.
  - **Initial sync on root connect**: `_connect_root_signals()` now calls `_sync_materials_from_root()`
    and `_sync_surface_paint_from_root()` so existing materials/surface data appear immediately.
  - **Initial selection state on startup**: plugin pushes cached editor selection to dock in
    `_enter_tree()`, so Selection Tools visibility is correct from first frame.
  - **Compact toolbar**: single-char button labels (D, S, +, -, P, ▲, ▼) with full descriptions in
    tooltips. VSeparator before extrude buttons. Labels update from keymap.
  - **UV Justify grid**: 3x2 GridContainer layout replaces cramped 2-row HBoxContainer.
  - **Autosave warning** defined in dock.tscn (was runtime-created Label).
- **Customizable keymaps** (`hf_keymap.gd`): all keyboard shortcuts are now data-driven via
  `HFKeymap` instead of hardcoded `KEY_*` constants. Bindings stored as action → {keycode, ctrl,
  shift, alt} maps. `load_or_default()` reads `user://hammerforge_keymap.json` or falls back to
  built-in defaults. `matches(action, event)` replaces ~25 inline keycode checks in `plugin.gd`.
  `get_display_string()` provides human-readable labels (e.g. "Ctrl+Shift+F"). Toolbar button
  labels and tooltips update from keymap automatically. `set_binding()` + `save()` for rebinding.
- **User preferences** (`hf_user_prefs.gd`): application-scoped preferences that persist across
  sessions via `user://hammerforge_prefs.json`. Stores: default grid snap, autosave interval,
  recent files (max 10, deduplicated, MRU order), collapsed section states, last tool ID, HUD
  visibility. Separate from per-level settings in `hf_state_system.gd`. Loaded in plugin
  `_enter_tree()` and passed to dock.
- **Gesture poll system**: `can_activate()` and `get_poll_fail_reason()` on `HFEditorTool`;
  `can_start()` on `HFGesture`. Dock disables selection-dependent buttons (Hollow, Clip, Floor,
  Ceiling) when nothing is selected. Plugin guards keyboard shortcuts with early-exit when
  `hf_selection` is empty.
- **Tag-based reconciler invalidation**: `tag_brush_dirty()`, `tag_paint_dirty()`,
  `tag_full_reconcile()`, and `consume_dirty_tags()` on LevelRoot. Brush system tags dirty on
  create/delete/transform; tags full reconcile on structural operations (hollow, clip). Enables
  future selective reconciliation (skip unchanged geometry).
- **Batched signal emission**: `begin_signal_batch()` / `end_signal_batch()` on LevelRoot with
  depth-counted nesting. During a batch, signals are queued; on flush, brush add/remove/change
  signals are coalesced into a single `selection_changed` emission. Wired into state system
  transactions. `discard_signal_batch()` on rollback.
- **Declarative tool settings**: `HFEditorTool` now exposes `get_settings_schema()` returning an
  array of property descriptors (name, type, label, default, min, max, options). Dock
  `rebuild_tool_settings()` auto-generates CheckBox/SpinBox/LineEdit/OptionButton/ColorPickerButton
  from the schema. `get_setting()` / `set_setting()` with defaults from schema.
- **Status bar mode indicator**: dock status label now shows the active tool mode (Draw, Select,
  Extrude ▲/▼, Paint) with [dragging]/[extruding] suffix during active gestures. Updated on
  every HUD context refresh.
- **Input pass-through reorder**: external tool `dispatch_keyboard()` now runs before built-in
  keyboard shortcuts in `_handle_keyboard_input()`, allowing external tools to override keys.
- **GUT tests** for new systems: `test_keymap.gd` (16), `test_user_prefs.gd` (9),
  `test_dirty_tags.gd` (11) = 36 new tests. Total: 344 tests across 22 files.
- **Command collation** for undo/redo: consecutive similar operations (nudge, resize, paint)
  within a 1-second window are merged into a single undo entry. Prevents undo flooding during
  rapid drag/nudge sequences. Collation tags: `nudge`, `resize_brush`, `paint_brush`.
- **Transaction support** in `HFStateSystem`: `begin_transaction()` / `commit_transaction()` /
  `rollback_transaction()` for atomic multi-step operations (hollow, clip). Captures state
  snapshot on begin; restores on rollback.
- **Autosave failure notification**: threaded write errors now propagate to the UI via
  `autosave_failed` signal on LevelRoot. Dock shows a red warning label when autosave fails.
  Warning auto-hides after 30 seconds and reappears on subsequent failures.
- **Central signal registry** on LevelRoot: `brush_added`, `brush_removed`, `brush_changed`,
  `entity_added`, `entity_removed`, `selection_changed`, `paint_layer_changed`,
  `material_list_changed`, `face_selection_changed`, `state_saved`, `state_loaded`,
  `autosave_failed`. Subsystems emit these signals; UI subscribes instead of polling.
- **Material manager persistence**: `save_library()` / `load_library()` for JSON-based material
  palette save/load. Usage tracking via `record_usage()` / `release_usage()` /
  `find_unused_materials()`.
- **Entity definition system** (`hf_entity_def.gd`): data-driven `HFEntityDef` class with
  `classname`, `description`, `color`, `is_brush_entity`, `properties`, `scene_path`. Loads
  definitions from JSON (entities.json), falls back to built-in defaults. Brush entity class
  dropdown in dock populated from definitions instead of hardcoded strings.
- **Gesture tracker base class** (`hf_gesture.gd`): `HFGesture` base for encapsulated input
  gestures. Holds root, camera, positions, numeric buffer. Subclasses override `update()`,
  `commit()`, `cancel()`. Ready for incremental adoption by new tools.
- **Declarative entity property forms**: when an entity is selected, the dock auto-generates
  typed controls (LineEdit, SpinBox, CheckBox, OptionButton, ColorPickerButton, Vector3) from
  the entity definition's `properties` array. Changes write to `entity.entity_data` and sync
  with Godot's Inspector. Built-in trigger defs now include `filter_class`, `start_disabled`,
  `wait_time` properties. Inspired by QuArK's `:form` system.
- **Duplicator / instanced geometry** (`hf_duplicator.gd`): create N copies of selected
  brushes with progressive offset. `HFDuplicator` RefCounted class with `generate()`,
  `clear_instances()`, `to_dict()`/`from_dict()` serialization. Dock UI: count SpinBox,
  X/Y/Z offset, Create/Remove Array buttons in Selection Tools section (Brush tab). Undo/redo
  via state snapshot. Inspired by QuArK's duplicator system.
- **Multi-format .map export adapters**: strategy-pattern writers for map export.
  - `HFMapAdapter` base class with `format_face_line()` and `format_entity_properties()`.
  - `HFMapQuake`: Classic Quake format (existing behavior, extracted).
  - `HFMapValve220`: Valve 220 format with UV texture axes from FaceData.
  - Format selector OptionButton in dock File section.
  - Entity properties now included in .map export.
- **Formalized plugin API** (`hf_editor_tool.gd` + `hf_tool_registry.gd`): base class and
  registry for custom editor tools. External tools (ID >= 100) loaded from
  `res://addons/hammerforge/tools/` at startup. Non-breaking Phase 1: built-in tools remain
  as-is; registry dispatches to external tools only.
- **Clipping tool:** Split a brush along an axis-aligned plane into two pieces.
  - `clip_brush_by_id(brush_id, axis, split_pos)` on `hf_brush_system.gd`.
  - Auto-detect split axis from face normal via `clip_brush_at_point()`.
  - Snaps split position to grid. Copies material, brush entity class, visgroups, and group ID.
  - Keyboard shortcut: Shift+X. Clip button in Selection Tools section of Brush tab.
  - Full undo/redo support via state snapshot.
- **Entity I/O system:** Source-style entity input/output connections.
  - Data model: output connections stored as `entity_io_outputs` meta on entity nodes.
  - Connection fields: output_name, target_name, input_name, parameter, delay, fire_once.
  - `add_entity_output()`, `remove_entity_output()`, `get_entity_outputs()` on entity system.
  - `find_entities_by_name()` resolves target references across entities and brushes.
  - `get_all_connections()` returns all I/O connections in the scene for visualization.
  - I/O connections serialized in `.hflevel` saves and undo/redo state.
  - Dock UI: collapsible "Entity I/O" section in Entities tab with Output, Target, Input,
    Parameter, Delay, Fire Once fields. Add/Remove buttons and connection ItemList.
  - I/O list auto-refreshes when selecting an entity.
- **Brush entity visual indicators:** Color-coded overlays for tagged brush entities.
  - `func_detail` brushes get cyan tint, `trigger_*` brushes get orange tint.
  - Semi-transparent MeshInstance3D overlay for visual differentiation in viewport.
- **Hollow tool:** Convert a solid brush into a hollow room with configurable wall thickness.
  - Creates 6 wall brushes (top/bottom/left/right/front/back) and removes the original.
  - Preserves material from the original brush. Keyboard shortcut: Ctrl+H.
  - Wall thickness SpinBox in Selection Tools section of Brush tab.
  - Full undo/redo support via state snapshot.
- **Numeric input during drag:** Type exact dimensions while drawing or extruding brushes.
  - During base drag or height adjustment, type digits to set precise size.
  - Enter applies the value and advances/commits. Backspace edits. Escape cancels.
  - Numeric buffer displayed in the shortcut HUD during drag.
- **Brush entity conversion (Tie to Entity):** Tag brushes as brush entity classes.
  - Tie/Untie buttons in Selection Tools section (Brush tab) with class dropdown (func_detail, func_wall, trigger_once, trigger_multiple).
  - `func_detail` brushes are excluded from structural CSG bake (detail geometry).
  - `trigger_*` brushes are excluded from structural bake (collision-only volumes).
  - `brush_entity_class` meta persists in `.hflevel` saves and undo/redo state.
- **Move to Floor / Move to Ceiling:** Snap selected brushes to the nearest surface.
  - Raycasts against other brushes and physics bodies to find nearest surface.
  - Grid-snapped result. Keyboard shortcuts: Ctrl+Shift+F (floor), Ctrl+Shift+C (ceiling).
  - Buttons in Selection Tools section of Brush tab. Full undo/redo support.
- **Texture alignment Justify panel:** Quick UV alignment controls in the UV Editor section.
  - Fit, Center, Left, Right, Top, Bottom alignment modes.
  - "Treat as One" checkbox for aligning multiple selected faces as a unified surface.
  - Works with the existing face selection system.
- **Hammer gap analysis** documented in ROADMAP.md with prioritized wave plan.
- **Dock UX overhaul:** Consolidated from 8 tabs to 4 (Brush, Paint, Entities, Manage).
  - `HFCollapsibleSection` (`ui/collapsible_section.gd`) with HSeparator, indented content, persisted collapsed state.
  - **Brush tab** (was Build): shape, size, grid snap, material, operation mode, texture lock, plus contextual **Selection Tools** section (hollow, clip, move, tie, duplicator — visible when brushes selected).
  - **Paint tab** (merged FloorPaint + SurfacePaint + Materials + UV): 7 collapsible sections. UV Justify uses 3×2 grid layout.
  - **Manage tab**: Bake, Actions (floor/cuts/clear), File, Presets, History, Settings, Performance, plus Visgroups & Cordon.
  - "No LevelRoot" banner and autosave warning defined in dock.tscn.
  - Compact toolbar: single-char labels (D, S, +, -, P, ▲, ▼) with tooltips. VSeparator before extrude buttons.
  - Paint/material sync is signal-driven (instant). Form label widths standardized to 70px. +/- buttons 32px wide.
  - Tab contents built programmatically via `_build_paint_tab()`, `_build_manage_tab()`, `_build_selection_tools_section()`.
- **Sticky LevelRoot discovery:** Users no longer need to re-select LevelRoot after clicking other nodes.
  - `plugin.gd`: `_handles()` returns true for any node when a LevelRoot exists; `_edit()` keeps `active_root` sticky; deep recursive tree search via `_find_level_root_deep()`.
  - `dock.gd`: sticky `level_root` reference in `_process()`; deep recursive search via `_find_level_root_in()` / `_find_level_root_recursive()`.
- **Visgroups (visibility groups):** Named groups (e.g. "walls", "detail") with per-group show/hide.
  - `HFVisgroupSystem` subsystem manages CRUD, membership (stored as node meta), and visibility refresh.
  - Nodes in ANY hidden visgroup are hidden (Hammer semantics). Nodes not in any visgroup stay visible.
  - Dock UI: visgroup list with [V]/[H] toggle, New/Add Sel/Rem Sel/Delete buttons in Manage tab.
  - Full serialization: visgroups persist in `.hflevel` saves and undo/redo state.
- **Brush/entity grouping:** Persistent groups that select and move together.
  - Single group per node via `group_id` meta. Auto-generated or named groups.
  - Ctrl+G groups selection, Ctrl+U ungroups. Clicking a grouped node selects all group members.
  - Dock UI: Group Sel / Ungroup buttons in Manage tab.
  - Groups persist in `.hflevel` saves and undo/redo state.
- **Texture lock:** UV alignment preserved when moving or resizing brushes.
  - Per-projection-axis UV offset and scale compensation in `face_data.gd`.
  - Supports PLANAR_X/Y/Z and BOX_UV projections. Skips CYLINDRICAL.
  - Toggle via `texture_lock` property on LevelRoot (default: on).
  - Dock UI: "Texture Lock" checkbox in Build tab.
  - Persists in `.hflevel` settings.
- **Cordon (partial bake):** Restrict bake to an AABB region.
  - Brushes outside the cordon AABB are skipped during collection and CSG assembly.
  - Yellow wireframe visualization via ImmediateMesh (12 AABB edge lines).
  - "Set from Selection" computes merged AABB of selected brushes + margin.
  - Dock UI: Enable checkbox, min/max spinboxes, "Set from Selection" button in Manage tab.
  - Persists in `.hflevel` settings.
- **GUT unit test suite** with 344 tests across 22 test files:
  - `test_visgroup_system.gd` (18 tests): CRUD, visibility, membership, serialization.
  - `test_grouping.gd` (9 tests): group creation, meta, ungroup, regroup, serialization.
  - `test_texture_lock.gd` (10 tests): UV compensation for all projection types.
  - `test_cordon_filter.gd` (10 tests): AABB filtering, chunk collection, chunk_coord utility.
  - `test_entity_props.gd` (12 tests): entity property form defaults, roundtrip capture/restore.
  - `test_duplicator.gd` (7 tests): instance count, offset, clear, serialization, edge cases.
  - `test_map_export.gd` (19 tests): Quake/Valve220 face formats, auto-axes, projections.
  - `test_tool_registry.gd` (25 tests): registration, activation lifecycle, dispatch, deactivation.
- CI workflow now runs GUT tests alongside gdformat/gdlint checks.
- Bake progress updates with chunk status in the dock.
- Bake Dry Run action for preflight counts and chunk estimates.
- Validate Level action with optional auto-fix for common issues.
- Missing dependency checks before bake/export.
- Autosave rotation with timestamped history files.
- Performance panel with brush, paint memory, chunk, and bake time stats.
- Settings export/import for editor preferences.
- Sample levels: minimal scene and stress test scene.
- Install + upgrade guide with cache reset steps.
- Design constraints document to make tradeoffs explicit.
- Data portability guide for `.hflevel`, `.map`, and `.glb`.
- Demo clip checklist and naming convention doc.
- Roadmap and contributing guidelines.
- **Extrude Up / Extrude Down tools** for extending brush faces vertically:
  - Click any brush face and drag to create a new box brush extruding from that face.
  - Extrude Up (green preview) and Extrude Down (red preview) with grid-snapped height.
  - Full undo/redo support via `_commit_brush_placement`.
  - Inherits source brush material automatically.
  - New `HFExtrudeTool` class (`hf_extrude_tool.gd`) using `FaceSelector` raycast.
  - Toolbar buttons (Ext+/Ext-) in same button group as Draw/Select.
  - Keyboard shortcuts: U (Extrude Up), J (Extrude Down).
  - Input state machine: added `EXTRUDE` mode to `HFInputState`.
  - Shortcut HUD: two new views (extrude idle, extruding active).
- **Multi-layer heightmap integration** for floor paint:
  - Heightmap import (PNG/EXR) and procedural noise generation (FastNoiseLite) per paint layer.
  - Per-cell material IDs and blend weights stored alongside existing bitset data.
  - Heightmap-displaced mesh generation via `HFHeightmapSynth` (SurfaceTool with per-vertex displacement).
  - Four-slot blend shader (`hf_blend.gdshader`) using UV2 channel for per-chunk blend maps (RGB = slots B/C/D), with default terrain colors, configurable grid overlay, and tint-compatible texture support.
  - Blend paint tool (`HFStroke.Tool.BLEND = 5`) for painting material blend weights on filled cells.
  - Auto-connector tool (`HFConnectorTool`) generating ramp and stair meshes between layers at different heights.
  - Foliage populator (`HFFoliagePopulator`) with height/slope filtering and MultiMeshInstance3D scatter.
  - Heightmap floors bake directly into output (bypass CSG) with trimesh collision shapes.
  - Dock UI: Heightmap Import/Generate buttons, Height Scale and Layer Y spinboxes, Blend Strength + Blend Slot controls.
- **Four-slot terrain blending** for heightmap floors:
  - New blend map format (RGB weights for slots B/C/D, slot A implicit).
  - Per-layer terrain slot textures + UV scales.
  - Blend Slot selection in the Floor Paint tab.
- **Region streaming** for floor paint:
  - Region-based loading/unloading of paint chunks.
  - `.hfr` region files alongside `.hflevel` with a region index.
  - Floor Paint tab controls for streaming settings + region grid overlay.
- Floor paint brush shape selector (Square or Circle) in the Floor Paint tab.
- Per-face material palette with face selection mode.
- Dynamic context-sensitive shortcut HUD that updates based on current tool and mode.
- Comprehensive tooltips on all dock controls (snap buttons, bake options, paint settings, etc.).
- Selection count indicator in the status bar ("Sel: N brushes").
- Paint tool keyboard shortcuts: B (Brush), E (Erase), R (Rect), L (Line), K (Bucket).
- Color-coded pending cuts: orange-red with high emission to distinguish from applied subtract brushes.
- Color-coded error/warning status messages with auto-clear timeout.
- Sample material resource for palette testing (`materials/test_mat.tres`).
- UV editor for per-face UV editing.
- Surface paint tool with per-face paint layers and texture picker.
- Bake option: Use Face Materials (bake per-face materials without CSG).
- Dock reorganized: Floor Paint and Surface Paint tabs.

### Changed
- Dock consolidated from 8 tabs to 4 (Brush, Paint, Entities, Manage). Selection-dependent tools (hollow, clip, move, tie, duplicator) moved from Manage → Brush tab's contextual Selection Tools section.
- Build tab renamed to **Brush** tab; bake options and editor toggles moved to Manage tab.
- FloorPaint, SurfacePaint, Materials, and UV tabs merged into single **Paint** tab with collapsible sections.
- Manage tab trimmed: Actions section now contains only floor/cuts/clear. Toolbar uses single-char labels with tooltips.
- Paint layer/material/surface paint sync changed from 10-frame polling to signal-driven instant updates.
- LevelRoot discovery is now "sticky": selecting non-LevelRoot nodes no longer breaks viewport input.
- Plugin `_handles()` uses deep recursive tree search and accepts any node when a LevelRoot exists.
- Dock `_process()` uses sticky reference; only nulls `level_root` when node is removed from tree.
- Brush delete undo now uses brush IDs and `create_brush_from_info()` snapshots for stability.
- New brushes placed via direct placement now receive stable brush IDs.
- Standardized editor actions under a single undo/redo helper with state snapshots.
- Paint Mode can target either floor paint or surface paint.
- .hflevel now persists materials palette and per-face data.
- .hflevel now persists per-chunk `material_ids`, `blend_weights` (+ _2/_3), `heightmap_b64`, `height_scale`, and terrain slot settings.
- Floor paint layers with heightmaps route to `HFHeightmapSynth` (MeshInstance3D) instead of CSG DraftBrush.
- Generated heightmap floors stored under `LevelRoot/Generated/HeightmapFloors`.

### Fixed
- Fixed undo collation never merging: `create_action()` was passing `can_collate` as
  `backward_undo_ops` (4th positional arg) instead of setting `merge_mode` to `MERGE_ENDS` (1).
  Undo history was flooding with one entry per nudge/resize/paint stroke. Now uses
  `merge_mode = 1` when collating and `false` for `backward_undo_ops`.
- Fixed undo collation merging across mismatched `full_state` scopes: added `full_state`
  equality check to collation eligibility. A `full_state=true` action no longer merges with
  a prior `full_state=false` run (or vice versa), preventing undo from restoring the wrong
  state scope.
- Fixed autosave warning timer crash: the timer closure assigned `null` to
  `_autosave_warning.visible` (a `bool`) when the dock was freed before the timer fired.
  Now guards with `is_instance_valid()` and skips the assignment entirely if the label is gone.
- Fixed material library `load_library()` silently remapping palette indices: empty or
  missing material entries were skipped with `continue`, compacting the array. Any data
  referencing materials by index (paint layers, brush face data) could point to the wrong
  material after reload. Now preserves `null` placeholder slots to keep indices stable.
- Fixed brush entity class dropdown becoming empty when `entities.json` contains only point
  entities: `_populate_brush_entity_classes()` now falls back to built-in defaults
  (func_detail, func_wall, trigger_once, trigger_multiple) when filtered brush defs are empty.
- Fixed `_on_tie_entity()` crash when dropdown has no items: now guards `item_count > 0` and
  `selected >= 0` before reading dropdown text, falling back to `"func_detail"`.
- Fixed duplicate arrays becoming non-removable after undo/redo or state restore:
  `restore_state()` now reapplies `duplicator_id` metadata on source brushes after rebuilding
  `_duplicators` from serialized data.
- Fixed creating a duplicate array on already-linked source brushes orphaning older groups:
  `create_duplicate_array()` now cleans up any existing duplicator that owns the same sources
  before creating the new one.
- Fixed external tools having no deactivation path when switching back to built-in tools:
  `activate_tool()` now nulls `_active_tool` after deactivating. Built-in tool selection
  (U/J keyboard shortcuts, dock toolbar button clicks) deactivates the active external tool
  via targeted `_deactivate_external_tool()` calls instead of per-frame checks.
- Fixed reconciler ghost references: `_index.erase(gid)` and `remove_child()` before `queue_free()` in `hf_reconciler.gd` to prevent stale node references.
- Fixed silent write failure in `hf_file_system.gd:export_map()` — added `file.get_error()` check after `store_string()`.
- Fixed unreachable guard in `hf_brush_system.gd` — `parts.size() == 0` after `String.split()` changed to `parts.size() < 2`.
- Reverted bloated `level_root.tscn` (11,652 lines of serialized FaceData back to 79-line template).
- Fixed LevelRoot discovery: plugin no longer loses `active_root` when clicking non-LevelRoot nodes; dock uses deep recursive search.
- Fixed dock disabled-state handling for SpinBox controls to avoid invalid `disabled` property assignments.
- Fixed heightmap mesh disappearing on every regeneration (height scale change, second generate noise click). Root cause: `_clear_generated()` used `queue_free()` (deferred) but `reconcile()` ran immediately after, finding ghost nodes still in the tree. Fix: `remove_child()` before `queue_free()`.
- Fixed missing walls when heightmap is active (same `queue_free` timing root cause).
- Fixed heightmap mesh rendering as a featureless white pane. The blend shader required texture samplers (`material_a`/`material_b`) but none were assigned. Added default terrain colors (`color_a` green, `color_b` brown) and a cell grid overlay to the blend shader for immediate visual feedback without imported textures.
- Fixed `test_mat.tres` UTF-8 BOM that prevented Godot from loading the sample material.
- Fixed 59 "Invalid owner" errors during chunked bake: `_assign_owner` was called on chunk nodes before their parent container was added to the scene tree.
- Changed navmesh `cell_height` default from 0.2 to 0.25 to match Godot's NavigationServer3D map default, eliminating mismatch warnings.
- Added `_assign_owner_recursive()` so baked geometry (chunks, meshes, collision, navmesh) all get proper editor ownership in one pass after being added to the tree.
- Added CI workflow (`.github/workflows/ci.yml`) for automated `gdformat` and `gdlint` checks on push/PR.

### Refactored
- Dock UX: rewrote `dock.gd` to build Paint, Manage, and Selection Tools contents programmatically using `HFCollapsibleSection`.
- Dock UX: ~100 `@onready var` declarations changed to plain `var` (controls created in code, not in .tscn).
- Dock UX: `dock.tscn` reduced to ~320 lines (tab shells + toolbar + autosave warning; content populated by `_ready()`).
- Dock UX: collapsible sections now have HSeparator + indented content + persisted state. All 18 sections registered in `_all_sections` dict.
- Replaced duck-typing in `baker.gd` (`has_method("get_faces")/.call()`) with typed `DraftBrush` access.
- Added `_find_level_root_deep()` to `plugin.gd` for recursive LevelRoot discovery.
- Added `_find_level_root_in()` and `_find_level_root_recursive()` to `dock.gd` for deep tree search.
- Split `level_root.gd` from ~2,500 lines into thin coordinator (~1,100 lines) + 8 `RefCounted` subsystem classes in `systems/`.
- Introduced `input_state.gd` (`HFInputState`) state machine replacing 18+ loose drag/paint state variables.
- Replaced ~57 `has_method`/`call` duck-typing patterns in `plugin.gd` and `dock.gd` with direct typed calls.
- Added recursion depth limits and inner-array validation to `hflevel_io.gd` variant encoding/decoding.
- Added null-safety checks in `baker.gd` after `_postprocess_mesh()` and `ImageTexture.create_from_image()`.
- Plugin cleanup (`_exit_tree`) now uses `is_instance_valid()` + `queue_free()` instead of `free()`.
- Removed Godot 3 `Image.lock()`/`unlock()` remnants from `face_data.gd`.
- Added texture image cache in `face_data.gd` paint blending to avoid redundant `get_image()`/resize calls.
- Added early-exit in `plugin.gd` screen bounds calculation for objects fully behind the camera.
- Fixed paint blending loop in `face_data.gd` that only ran when the weight image needed resizing.
- Threaded .hflevel writes now log errors on file open failure and `store_buffer` errors.
- **Code quality audit** (~30 issues across 11 files):
  - Comprehensive duck-typing removal: `baker.gd` (typed `ArrayMesh` cast for lightmap/LODs), `hf_file_system.gd` (direct `GLTFDocument` calls), `plugin.gd` (direct `set_undo_redo`), `dock.gd` (6 sites: undo/redo, cordon visual, brush info, dependency checks).
  - Removed redundancies: duplicate null checks, unbounded `while true` loops, redundant `ensure_dir_for_path`, consolidated init guards.
  - Named constants: `MAX_BUCKET_FILL_CELLS`, `MAX_LAYER_ID_SEARCH`; `is_entity_node()` as primary public API.
  - Extracted `_deserialize_chunks_to_layer()` in `hf_paint_system.gd` (eliminated ~40-line duplication).
  - Fixed O(n²) in `capture_region_index()` via Dictionary lookup.
  - Extracted `_collect_all_chunks()` in `hf_bake_system.gd` (shared by `bake_chunked` and `get_bake_chunk_count`).
  - Added brush/material caching in `hf_brush_system.gd`: O(1) brush ID lookup, O(1) brush count, material instance cache.
  - Cordon visual: persistent `ImmediateMesh` reused via `clear_surfaces()`.
  - Extracted inline GLSL to `highlight.gdshader` file.
  - Added `build_heightmap_model()` on `hf_paint_tool.gd` (shared by 3 heightmap reconcile callers).
  - Signal-driven sync in `dock.gd`: replaced 17 per-frame property writes with signal handlers; paint/material/surface paint sync now fully signal-driven via LevelRoot signals; throttled perf updates (every 30 frames), flag-driven disabled hints; cached `_control_has_property()`.
  - Input decomposition in `plugin.gd`: split 260-line `_forward_3d_gui_input()` into ~50-line dispatcher + 7 focused handlers + shared `_get_nudge_direction()`.

### UX
- Dock now has 4 tabs (Brush, Paint, Entities, Manage) instead of 8 for faster navigation.
- Selection tools (hollow, clip, move, tie, duplicator) appear contextually in Brush tab when brushes are selected.
- Collapsible sections with separators, indented content, and persisted collapsed state across sessions.
- "No LevelRoot" banner at dock top guides users when no LevelRoot is found.
- Compact toolbar with single-char labels (D, S, +, -, P, ▲, ▼) and descriptive tooltips.
- Paint layer and material changes sync instantly (signal-driven, no 167ms polling delay).
- Wider +/- buttons (32px), standardized label widths (70px), UV Justify in clean 3×2 grid.
- LevelRoot stays active when clicking other scene nodes (sticky root discovery).
- Shortcut HUD now shows context-sensitive shortcuts (6 different views: draw idle, dragging base, adjusting height, select, floor paint, surface paint).
- HUD displays current axis lock state (e.g. "[X Locked]").
- Status bar errors appear in red, warnings in yellow, and auto-clear after a timeout.
- Bake failure now shows "Bake failed - check Output for details" instead of generic "Error".
- Pending subtract brushes are visually distinct (orange-red, high glow) from applied cuts (standard red).

### Documentation
- Added texture/materials guide, development/testing guide, and updated README/spec/user/MVP docs.
- Updated spec, development guide, MVP guide, and README to reflect subsystem architecture.
- Updated all docs to document new UX features: dynamic HUD, tooltips, shortcuts, pending cut visuals.
- Updated all docs for multi-layer heightmap integration: heightmap workflow, blend tool, connectors, foliage, bake integration.
- Added TrenchBroom + QuArK architecture learnings document (`project_editor_learnings.md`).
- Updated ROADMAP with QuArK-inspired items: declarative entity property forms, multi-format `.map`
  export adapters, duplicator/instanced geometry, formalized plugin API, bezier patches.
- Updated SPEC entity definitions section with planned declarative property forms.
- Updated data portability doc with planned multi-format `.map` export strategy.
- Updated CONTRIBUTING, DEVELOPMENT, SPEC, MVP guide, user guide, texture/materials doc, and
  README with command collation, transactions, signals, entity defs, gestures, material persistence,
  autosave failure, and all code review bugfixes.
- Updated DEVELOPMENT test table with actual test counts: entity_props (12), duplicator (10),
  map_export (19), tool_registry (25). Total: 308 tests across 19 files.

## [0.1.1] - 2026-02-05

### Added
- Live paint preview while dragging for Brush/Erase/Line/Rect.
- Paint preview reconciliation without node churn (dirty chunk scope).
- Bucket fill improvements and guardrails.
- Paint layer persistence in .hflevel files.
- Log capture guidance for exit-time Godot errors.

### Changed
- Paint preview now updates generated floors/walls in real time.
- Paint tool default radius behavior tuned (radius 1 = single cell).
- Paint chunk indexing now floors correctly for negative coordinates.

### Fixed
- Quadrant mirroring caused by incorrect chunk indexing of negative cells.
- Live preview not appearing until mouse-up.
- Corrupt entity icon references updated in docs.

### Documentation
- Major refresh across README, spec, and guides to reflect paint system and workflows.

## [0.1.0] - 2026-02-04

### Added
- CAD-style brush creation: drag a base, then set height and commit with a second click.
- Modifier keys: Shift (square base), Shift+Alt (cube), Alt (height-only).
- Axis locks for drawing (X/Y/Z).
- Draw/Select tool toggle in the dock.
- Collapsible dock sections for Settings, Presets, and Actions.
- Physics layer presets for baked collision via dock dropdown.
- Live brush count indicator with performance warning colors.
- New SVG icon for LevelRoot in the scene tree.
- Paint Mode: pick an active material and click brushes to apply it in the viewport.
- Active material picker in the dock (resource file dialog for .tres/.material).
- Hover selection highlight (AABB wireframe) when using Select.
- Select tool now yields to built-in gizmos when a brush is already selected.
- Prefab factory for advanced shapes with dynamic shape palette.
- Added wedges, pyramids, prisms, cones, spheres, ellipsoids, capsules, torus, and platonic solids.
- Mesh prefab scaling now respects brush dimensions (capsule/torus/solids).
- Native 4-view layout guidance (uses Godot's built-in view layout).
- Multi-select (Shift-click), Delete to remove, Ctrl+D to duplicate.
- Nudge selected brushes with arrow keys and PageUp/PageDown.
- Auto-create LevelRoot on first click if missing.
- Create Floor button for quick raycast surface setup.
- Pending Subtract cuts with Apply/Clear controls (Bake auto-applies).
- Cylinder brushes, grid snap control, and colored Add/Subtract preview.
- Commit cuts improvements: multi-mesh bake, freeze/restore committed cuts, bake status, bake collision layer control.
- Viewport DraftBrush resize gizmo with face handles (undo/redo friendly).
- Gizmo snapping uses grid_snap during handle drags.
- Line-mesh draft previews for pyramids, prisms, and platonic solids.
- Chunked baking via LevelRoot.bake_chunk_size (default 32).
- Entities container (LevelRoot/Entities) and is_entity meta for selection-only nodes (excluded from bake).
- Entity definitions JSON loader (res://addons/hammerforge/entities.json).
- DraftEntity schema-driven properties with Inspector dropdowns (stored under data/, backward-compatible entity_data/).
- Create DraftEntity action button in the dock.
- Editor-only entity previews (billboards/meshes) driven by entities.json.
- Collision baking uses Add brushes only (Subtract brushes excluded).
- Playtest FPS controller with sprint, crouch, jump, head-bob, FOV stretch, and coyote time.
- Playtest button workflow: bake + launch current scene.
- Player start entity support (entity_class = "player_start").
- Hot-reload signal for running playtests via res://.hammerforge/reload.lock.
- Floor paint system with grid-based paint layers and auto-generated floors/walls.
- Paint tool selector (Brush/Erase/Rect/Line/Bucket), radius control, and layer picker in the dock.
- Stable-ID reconciliation for generated paint geometry to avoid node churn.
- .hflevel persistence for paint layers and chunk data.

### Changed
- Disabled drag-marquee selection in the viewport to avoid input conflicts.
- Paint Mode now routes to the floor paint system (material paint is reserved for a future pass).

### Fixed
- Selection picking now works for cylinders and rotated brushes.
- Height drag direction now matches mouse movement (up = taller).
- Guarded brush deletion to avoid "Remove Node(s)" errors.
- Dock instantiation issues caused by invalid parent paths.
- Commit cuts bake now neutralizes subtract materials so carved faces don't inherit the red preview.
- Playtest spawning now waits for runtime tree readiness to avoid transform warnings.
- Playtest now bakes before hiding draft geometry, so you can see brushes in-game.

### Documentation
- Added user guide and expanded LevelRoot explanation.
- Updated README, user guide, MVP guide, and spec for chunked baking and entity workflow.
- Documented selection limits and drag-marquee being disabled in the viewport.
- Expanded docs for floor paint workflow, layers, and persistence.
- Broad documentation refresh across README/spec/guides for floor paint, layers, and logs.
