# Changes after 0.3.2: full notes

The changelog entries for the work merged after 0.3.2, as they were first
written, up to 5 October 2026. That day `CHANGELOG.md` moved to one dated
line per change, grouped by week, and these were kept here word for word.
The short version is in [CHANGELOG.md](../CHANGELOG.md). From then on the
detail behind a change is in its pull request.

## [Unreleased]
### Added
- **A cut's confirmation says when a sculpt will be dropped** (#871). A piece
  of a sculpted face with three or five corners cannot hold the sculpt, and the
  only notice was a warning in the Output panel after the cut. The Clip, Carve
  and Hollow confirmations now add a line such as "1 sculpt cannot follow this
  cut and will be dropped". The previews count corners only, so they cost what
  they did. The warning after the cut stays.
- **Flip mirrors a sculpted displacement** instead of refusing the brush. The
  sculpt moves to the mirrored side with every height, blend value and custom
  offset, and each grid cell keeps its fold, so the terrain is mirrored exactly.
  Flipping back gives the original sculpt. A box keeps its resize handles, and a
  later resize keeps the mirrored sculpt the way round the flip left it. Taking a
  negative scale off a sculpted brush now works the same way. It used to leave
  the brush mirrored, with a warning that it would bake inside out. A sculpt
  with mirrored cells saves one new key, `flip_diagonals`, and nothing else in
  the file changes.

### Changed
- The GUT suite builds its levels from the real `LevelRoot` instead of some
  sixty hand-written stand-ins (#922). The stand-ins had drifted from the class:
  `grid_snap` 0.0 or 8.0 where a level starts at 0.5, `texture_lock` off where it
  is on, an entity check reading a meta nothing sets, and one file testing its
  own copy of the dirty tags. `tests/test_level_root_shims.gd` now refuses a test
  that declares the level's containers itself, or a script built in a test that
  starts a level setting somewhere the level does not.
- The last three test classes that copied `LevelRoot` members now use the real
  class, and the stand-in guard also refuses a test class that copies one of
  the level's enums or saved settings (#946). The drag tests had run at a
  `grid_snap` of 1.0, where a level starts at 0.5. The brush change tracker's
  stand-in is marked until #948 moves it.
- The brush change tracker's tests run on a real level with real brushes
  (#948). Its stand-in listed its own brushes and kept its own dirty list, so
  the level's brush walk, dirty tags and structure repair never ran under them.
  No test carries the `hf-allow-level-stand-in:` marker any more.
- Systems call `tag_brush_dirty()`, `tag_full_reconcile()` and the level's
  settings directly instead of first asking whether the root has them (#945).
  Every root is a real `LevelRoot` since #922, so a missing member is now an
  error rather than a quiet skip. The brush system still makes its own
  transform system in a running game, where the level does not build one.
- The brush change tracker calls the level's members directly (#952). Its
  branches for a root that is not a `LevelRoot` are gone: one counted a brush
  directly under the root as a draft, and another built a spare transform
  system. A missing member is now an error rather than a quiet skip.
- CI loads every script in the vibe harness and fails if one does not parse
  (#955). Nothing loaded them before, so #938 left a scenario calling a
  function that no longer existed and CI stayed green.
- The stand-in guard also refuses a script a test builds from source that
  copies one of the level's enums or saved settings, templates included
  (#951). Such a copy matched the level only until the level's default moved.
  The quick play, viewport key and `.hflevel` freshness tests now run on a real
  `LevelRoot`.
- The stand-in guard refuses a script a test builds from anything but one
  `"""` block, which is the only form its rules read (#957). Two stand-ins had
  hidden from it as strings joined with `+`. The validation and entity I/O
  vocabulary tests now run on a real `LevelRoot`.
- CI checks that each `root.name(` and `root.member.name(` call in the vibe
  harness names something a real level has (#958). Loading the scripts could
  not see these, because a scenario's root is a `Node3D` and most systems are
  untyped. Two scenarios had been skipping their own question behind a
  `has_method` or `has_signal` check: `build-outdoors` called `create_default_spawn()` on the
  level and then looked for the spawn by a meta, and `save-as` listened for an
  `hflevel_saved` signal that is now `hflevel_save_completed`.
- CI packs the GUT shards by each script's measured time, from
  `tests/.durations.json`, instead of dealing them out by name (#920). Adding a
  test file no longer moves every later file to another shard, the shards
  finish close together, and a failing shard's summary names the failing tests.
  The heightmap cap test reaches the cap on a small grid, which took it from
  the slowest script in the suite to about two seconds.
- CI fails when GUT ends a run with orphans or warnings, and names the script
  and test (#923). The "unfreed children" warning depends on which script ran
  before, so it is shown as an annotation rather than failing the run. Two `baker.gd` nodes from #911 and two scripts whose last
  test left a queued node behind are fixed.
- CONTRIBUTING gives one numbered setup for running the tests on a fresh clone,
  and says the import is required: without it GUT runs nothing and exits 0
  (#924). The pull request template and the features page point at
  `tools/run_local_checks.py` instead of keeping their own lint commands, and
  `run_local_checks.py --check` fails if either names one CI does not run.
  `check_script_warnings.py` says to set `GODOT` instead of printing a
  traceback.
- The VS Code test tasks run one file through `-gselect` instead of the whole
  suite, run it once on Windows, exit when done, and link script errors in the
  project's own files without flooding the Problems panel with GUT's frames
  (#925). `run_local_checks.py --check` refuses `-gtest=` in a task.
- CI no longer commits the published test counts to a pull request (#916). The
  commit forced a second CI round and made any two open pull requests that
  added tests conflict. The totals are now refreshed when a release is cut, and
  CI prints them in the run summary. The static tests badge is gone; the CI
  status badge beside it stays.
- Dependabot waits seven days before proposing a release, and the zizmor audit
  now reads `.github/dependabot.yml` as well as the workflows (#918).
- The path, polygon and measure tools draw on one overlay built by
  `HFEditorTool.make_overlay_mesh()` (#904), the hotkey palette and the shortcut
  dialog list actions through `HFKeymap.grouped_actions()` (#906), and region
  files and undo snapshots pack a paint chunk through
  `HFPaintLayer.packed_chunk()` (#900).
- The brush preview resolves a face's material through the same
  `FaceData.resolved_material()` the bake uses (#902), and validation walks the
  baked meshes with the bake's own collector (#903).
- Both `.map` adapters write their offsets, rotations and axes through one
  number formatter on `HFMapAdapter` (#905).

### Fixed
- **Check Only reports a cut that only overlaps a door** (#942). A brush tied to
  an entity class bakes from its own faces and no cutter reaches it, but
  validation counted it as solid ground, so a cut that carved nothing in the
  bake went unreported.
- **Brush presets survive an addon upgrade** (#930). They were saved in
  `addons/hammerforge/presets`, which the upgrade steps replace, so every
  preset went with it. They now live in `res://hammerforge_presets/`, and
  presets in the old folder move across once on load. The folder is made when
  the first preset is saved rather than in every project on every load.
- **A click in a scene that is not a level leaves it alone** (#932). Draw is
  the default tool, so one click to select a mesh in, say, a player scene added
  a LevelRoot to it and took the selection. A first Draw click now creates a
  level only in a new, empty 3D scene. Anywhere else the click selects as
  usual, and the dock says once how to create a level.
- **An Entity panel edit is an undo step** (#931). The panel wrote the field
  straight onto the entity, so Ctrl+Z after an edit undid the step before it,
  and right after creating an entity that took the entity away. Typing in one
  field makes one step.
- **One key press in the viewport runs once** (#927). A key HammerForge handled
  went on to Godot's shortcuts and to HammerForge's own second key hook, so one
  Ctrl+D made two duplicates, Ctrl+V also pasted Godot's clipboard, PgDown
  nudged and snapped to the floor, and E, Q, T, U, Y and P also flipped Godot's
  tool modes and toggles. The key is now consumed. Where Godot's 3D editor binds
  the same key, it goes back to Godot while only Godot nodes are selected.
  Selection Filters moved from Shift+F, which is Godot's Toggle Freelook, to
  Alt+F. Ctrl+D typed in the Scene dock's Filter Nodes box no longer
  duplicates, and `user://hammerforge_keymap.json` takes key names such as
  `"F"`. The guide said the file was created on first run; it is not.
- **A prefab save asks before it replaces a file** (#929). Quick Save named the
  file after what was selected, so a second box saved over the first box's file
  and the instances linked to it followed; it now takes the next free name, such
  as `box_2`. The Prefabs panel's Save and Save Linked ask before replacing an
  existing prefab. The panel's Save also kept its own copy of the save that
  skipped the safe file name from #667, so `../escape` landed beside
  `project.godot` and `wall/trim` wrote nothing. It now goes through the same
  save as everything else.
- **Autosave keeps running after a scene tab switch** (#928). The editor takes a
  scene out of the tree when you switch tabs, and putting it back did not start
  autosave or the subtract preview again, so one switch ended autosave for the
  session while the Inspector still said it was on.
- **The release workflow refuses a tag that does not match `plugin.cfg`, and
  pushes the `release` branch last** (#919). A tag pushed before the version
  bump shipped the new code under the old version's name. The branch is now
  committed, its archive checked and the zip attached before the push, and a
  run started by hand is a dry run that pushes nothing.
- **A door stays open for its whole wait** (#910). The self-close timer started
  when the door started opening, so a door slower to open than its wait turned
  back half way, and a faster one stayed open for less than it was set to. The
  count now starts when the door gets there, and a Close on the way leaves
  nothing behind to close it again.
- **The shortcut dialog lists Rotate, Flip and Reset Rotation** (#906). Its
  list of categories had no Transform, so those four had bindings and no row.
- **A wedge, cylinder or cut brush imported from a `.map` is textured properly**
  (#909). The import builds a brush that is not a box from face records that
  name no projection, and those read as PLANAR_Z, so its floors and its east and
  west walls had every corner on one line of the texture. A record that names
  none, or names one that is not a projection, now reads as Box UV, which is
  what a new face starts on. Validation's fix for a bad projection does the same.
- **Wall textures stand the right way up** (#907). A wall's V ran up the wall,
  and Godot reads V = 0 as the top row of an image, so every wall and every
  Cylindrical face was drawn upside down, in the viewport and in the bake. The
  planar axes are now qbsp's: V runs down a wall, and an X wall's U runs along
  -Z. A Classic Quake export now opens with its walls the way the viewport shows
  them. In a level made before this, every face somebody aligned, painted or
  edited by hand keeps exactly the look it had, with its paint and its hollow and
  array records untouched; faces nobody touched turn the right way up.
  **Re-project UVs** puts an old face on the new axes. The UV editor draws V
  down the canvas to match. A face record gains `legacy_wall_axes`, a scene gains
  `face_axes_version`, and `uv_format_version` goes to 3.
- **A turned brush converts to a heightmap and previews its cut over the right
  ground** (#901). Brush to Heightmap and the subtract preview each boxed a
  brush's size round its position when it had no mesh to read, which is the
  wrong box for a brush turned on its side. Both now ask the bake's bounds,
  which read the mesh, then the faces, then the size through the transform.
- **A rotated face keeps its rotation in a Valve 220 export** (#899). Valve 220
  readers project with the texture axes as written and leave the rotation field
  alone, and the export wrote the axes unturned, so every rotated face opened
  unrotated in another editor. The axes now go out turned by the face's rotation.
  A face with no rotation writes the same line as before, and the import still
  reads the rotation back.
- **A `.map` face's texture scale and offset are written and read in texels**
  (#894). Other editors read both in texels of the texture, and the export wrote
  them in repeats, so a 64 pixel texture at the default alignment opened 64 times
  too large. They now go through the size of the palette texture the face shows,
  or 64 pixels for a face with none, both ways. A file from another editor now
  imports with its alignment instead of at the default, and a round trip still
  comes back exact.
- **Similar Faces and Similar Brushes select the same things from the command
  and the Selection Filters popover** (#896, #897). Each had its own copy of the
  match, and the command's also picked hidden brushes, so a texture or a move
  applied next landed on something nobody could see. Both now ask one function
  each, which leaves hidden brushes out.
- **The Valve 220 export writes the Box UV axis the viewport draws** (#895). It
  worked the axis out again from the plane points it writes. On a box turned
  exactly 45 degrees away from the origin, rounding put that normal past the tie
  the other way, so some faces were written with the other axis and textured
  differently in another editor. It now asks the face.
- **A hollow or a flight made before the face-order fix reads correctly after a
  reopen** (#878). Its records were taken over the pieces in the order the cut or
  the stairs builder made them, and a reopen puts a box piece into the builder's
  order, so every wall counted as reworked and every step as edited until one
  Re-hollow or Update. Each piece is now checked against its faces as they were
  loaded, and only a piece that still matches has its record taken again, so a
  piece edited before the save still counts. A box piece read from an older
  `.hflevel` is put into the builder's order as well, so a face selected on it is
  the same face after a resize.
- **Resizing a capsule is cheap enough to drag** (#860). A capsule turned its
  mesh of a few thousand triangles back into faces on every resize, 78 to
  91 ms each, and a handle drag resizes on every motion event. Its faces are now
  built once for each case, with no middle and with one, and placed from the
  radius and the middle's length: 3.9 ms stretched and 6.5 ms without a middle,
  measured the same way. The faces match a merge at the same size corner for
  corner, and a resize keeps every face and what is on it.
- **Update Array asks before it rebuilds over a stroke on a copy** (#875). Copies
  of a painted brush start with its paint layers, so a stroke on one landed in a
  layer it already had. The edit check left the paint masks out to stay cheap on
  every selection change, so it saw nothing, and the first Update press rebuilt
  over the stroke without a word. The press reads the masks now, once, and asks
  twice as it does for any other edit. Detach keeps the stroke.
- **Box UV projects a stretched slope along the axis it really faces** (#887).
  The axis was picked from the normal carried by the brush's basis alone, which
  leans on a brush stretched with Godot's scale gizmo. A 45 degree slope on a
  wedge four times as tall faces mostly along Z and was projected along Y, so its
  texture was drawn about four times too long, and the Valve 220 export wrote a
  different axis from the one on screen. A stretched slope's texture changes
  once, to the right axis, when the level opens. Nothing else moves.
- **A stretched brush bakes its slopes lit the way they face** (#884). A brush
  stretched with Godot's scale gizmo baked every slanted face with a normal that
  leaned towards the stretched axis, up to 60 degrees off on a cylinder at
  (4, 1, 1), so a ramp or a round wall was lit as though it faced elsewhere. The
  same lean put a stretched slope in the wrong Walls, Floors or Ceilings filter,
  kept Select Similar from matching it, tilted Clip to Face Plane, sent Extrude
  off at an angle, moved a sculpt stroke off the cursor and stood occluders on
  the wrong plane. Normals now go through the inverse transpose. A level with no
  stretched brush bakes exactly as before.
- **A `.map` HammerForge exported brings back each face's texture alignment**
  (#885). Import kept the texture name and dropped the offset, scale and
  rotation, so a level exported and read back lost every hand-aligned face. It
  reads them back in both formats now. A file from another editor still arrives
  at the default alignment: its numbers are in texels, and a `.map` does not say
  how big the texture is.
- **A sculpt stroke in the viewport reaches the face.** The check that a stroke
  was on its face assumed the opposite corner order to the one faces have, so it
  turned away every stroke on every face, and Raise, Lower, Smooth, Noise and
  Alpha did nothing in the viewport. The dock's Noise and Smooth buttons were
  not affected.
- **`tools/wait_for_ci.py` reads an all-digit short SHA as a commit** (#876).
  Digits alone were always a pull request number, so `3413602`, the squash of
  #874, was looked up as pull request #3413602 and the wait died. Seven digits
  or more are a commit now. Shorter ones are still a pull request.
- **A full GUT run prints no warnings or deprecations** (#882). Seven
  `wait_frames()` calls are `wait_physics_frames()`, which GUT 9.6 forwarded
  them to anyway. The history browser and hotkey palette tests free their
  widget at once instead of queueing it, so none is left over when the script
  ends, and one float is compared with a float.
- **A cut keeps Cylindrical UVs, and the paint on them, where they were**
  (#868). Cylindrical UVs are measured about the brush's own middle and over the
  face's own height. Each piece of a cut is re-centred on a brush of its own, so
  a clip, carve or hollow turned the texture on every face and stretched it over
  the cut ones, and the paint moved with it: a point on a clipped box went from
  V 0.81 to 0.5. Each piece of a Cylindrical face now keeps the UVs its face
  showed at its corners. Planar and Box UVs never moved and are left as they
  are.
- **Bevel and Inset keep a sculpt on the surface it was on** (#870). Both move a
  face's corners and left its sculpt as it was, so the whole grid was squeezed
  onto the smaller face: a bevel on a sculpted top moved 20 of its 25 grid
  points, up to 2.25 units, and an inset left the ring around the inset flat.
  Each sculpt is now trimmed onto the face's new corners, the same way a cut
  trims one. A flat inset sculpts the ring as well, and a raised inset lifts its
  sculpt with it.
- **Flip judges whether a box's faces look alike the way the rest of the editor
  does** (#864). It kept its own list of what makes up a face's look, and #859
  was the field that list missed. It asks `FaceData.appearance_matches()` now,
  so a field added to the look reaches Flip as well. A face with custom UVs
  counts as different from the rest, like one with paint or a sculpt, since
  those UVs belong to its corners.
- **A cylinder's `.map` export puts each texture on its own side** (#880). On a
  cylinder stretched with Godot's scale gizmo, 12 of its 18 planes went out with
  a neighbouring side's texture: the export matched planes to faces by
  transformed normals, and those lean towards the stretched axis. It matches
  them in the brush's own frame now. A cylinder with 5, 6 or 7 sides, or any
  count that is not a multiple of four, also exported a prism turned against the
  one on screen, so none of its walls lay where they were drawn. The export now
  starts its ring where Godot's cylinder mesh does.
- **Reopening a scene no longer reads a hollow or a flight of stairs as reworked**
  (#873, #867). A piece that Clip, Carve, Hollow or the stairs generator leaves as
  a box listed its faces in its own order, and a box rebuilds into the builder's
  order whenever its scene opens. So after a save and reopen every wall of a box
  hollow counted as reworked and Re-hollow asked twice, every step of a flight
  counted as edited, and Update then put each step face's paint on another side.
  The same reorder moved a face selection onto another face on a piece's first
  resize, and the `.map` export wrote each plane of a fresh cut piece with a
  neighbour's texture. Box pieces are now stored the way the builder makes them.
- **Re-hollow counts a stroke on a wall of a painted solid** (#869). Walls now
  start with their solid's paint, so a stroke on one landed in a layer the wall
  already had. Nothing the count read had changed, so Re-hollow put the solid's
  paint back over the stroke without warning. The hollow now records what each
  wall's paint masks hold, and a stroke counts the wall like any other edit.
  Arrays still skip the masks, so selecting part of an array costs no more.
- **Clip, Carve and Hollow keep surface paint and sculpts** (#863). Every piece
  came out unpainted and flat, with no warning, so carving a doorway through a
  finished wall wiped its paint. Each piece face now keeps the paint that was on
  that part of the face, in layers of its own. A sculpted face that is cut into
  four-cornered pieces keeps its sculpt on each of them, resampled onto the same
  surface. A piece with any other number of corners cannot hold a sculpt, so it
  comes out flat and a warning names the brush.
- **A clipped box keeps each face's texture through a resize and a reopen.** A
  cut lists a piece's faces in its own order, and a box rebuild handed face data
  over by position in that list. So the first resize of a clipped, carved or
  hollowed box moved most of its textures to other faces, and so did reopening
  the scene, since a box rebuilds when its scene opens. A box whose faces are not
  in the order it builds them now pairs them by the way they face.
- **A face keeps its `.map` texture name through a rebuild, a duplicate and a
  cut** (#859). The export writes that name when the palette has no slot for the
  face, and the name is the surface's behaviour: `AAATRIGGER` is a trigger. Every
  primitive rebuild dropped it, and every primitive rebuilds when its scene opens,
  so an imported trigger box lost it on a resize, a Godot Duplicate, or just a save
  and reopen, and went back out as a plain solid. Clip, Carve, Bevel, Inset and
  Clip to Convex dropped it from every face they made, a generated structure's
  Update dropped it from every piece, and Flip could leave each name on the face
  across from where it belonged. A face made from another face now takes the
  palette slot and the name together.
- **A sculpt is saved with the scene** (#854). Ctrl+S dropped every face's
  displacement, so a scene reopened flat and the next bake flattened the
  terrain too. Only the `.hflevel` kept it. A scene with no sculpt saves
  exactly as before.
- **A resize keeps a sculpt on a face saved with turned corners** (#846). A box
  flipped by a build from before Flip learned to mirror sculpts was saved with
  some faces starting at a different corner. A displacement added to one of
  those faces later turned half a turn on the next resize, even a resize to
  the same size, and custom UVs turned with it. A rebuild now matches each
  face's corners against the face it replaces and relabels the sculpt and the
  UVs to its own corner order. A face that already starts where the box starts
  it is handed over exactly as before. A sculpt relabelled a quarter turn round
  saves the `flip_diagonals` key that mirrored sculpts use.
- **A displaced face is wound the way its face is** (#845). Every triangle of a
  displacement grid was wound the opposite way, so a sculpt faced into its brush
  and was culled from outside, in the viewport and in the bake. The vertex
  normals were already right, and the saved grid is untouched.
- **Test Level runs the node each entity class names** (#840). Only the two
  exports built them, so in Test Level a `logic_timer` was a marker that never
  fired `OnTimer`, and a light lit nothing. The running level now swaps each
  marker for its node after the bake and rewires the I/O dispatcher. The
  editor's scene keeps its markers.
- **An entity scene can have any root, and a refused one no longer leaks**
  (#844). A `scene` whose root was not a `Node3D` was instantiated, refused
  and never freed, once per entity on every export and Test Level run. It now
  builds, the way a `class` can be any node since #826. The viewport preview
  still needs a `Node3D` to show, and now frees the scene when it cannot.
- **DEVELOPMENT.md and the spec no longer list a test count per file** (#837).
  Nothing wrote those numbers, and 44 of 89 in DEVELOPMENT.md and 12 of 24 in
  the spec had drifted. The tables keep each file and what it covers. The
  five suite totals are still written by CI.
- **The plugin loads in a project that turns on warnings for addons** (#836).
  Godot hides warnings from scripts under `addons/` by default, and 440 had
  built up unseen. Seven were a type inferred from a Variant, which Godot
  treats as an error, so opting addons in stopped the brush gizmo, the paint
  tools and the validation system from loading. All are fixed or marked with
  a reason, and CI now loads every plugin script with warnings raised to
  errors.
- **A `logic_timer` starts when the level loads** (#835). Nothing started one
  unless a `Start` input reached it, so a timer wired only by its `OnTimer`
  never fired. The new **Start On Load** property is on by default. Untick it
  for a timer that should wait for `Start`. A property a level stores no value
  for now exports at its class default, the value the inspector shows, rather
  than the engine's own.
- **`logic_timer` exports as a `Timer` and fires `OnTimer`** (#826). The export
  only built classes under `Node3D`, so every timer shipped as its editor marker,
  and nothing connected `timeout` to `OnTimer`. Any `Node` class now builds, and
  a definition can name the engine signal behind an output with the new
  `output_signals` key.
- **`func_wall` stays out of the world bake and answers Enable and Disable**
  (#827). It was treated as structural, so it merged into the static mesh and
  a wire to it found nothing. It now bakes the nonstructural way, and a named
  wall keeps its own node. The dispatcher handles Enable and Disable on baked
  brush entities: a wall hides and loses its collision, and a trigger stops
  detecting bodies.
- **Rewiring no longer lets a `trigger_once` volume or a fire once connection
  fire again** (#825). `wire()` cleared the fired state with everything else.
  It now keeps it for every source still alive. A rewire after a wired source
  was freed also stopped with a script error, and no longer does.
- **Play from Camera and Play Selected Area no longer save their temporary
  spawn or cordon into the scene** (#822). Godot saves the edited scene before
  a run, and both put the authored values back only after the launch. They now
  restore first and pass the camera pose or play area to the run in the launch
  request.
- **A refused `.hflevel` no longer moves streamed paint** (#823). The loader
  pointed the region path at the file before checking it, so after a malformed
  or newer file was refused, the next region unload wrote the open level's
  paint into the refused file's sidecar. The path now moves only once the file
  loads.
- **Load .hflevel no longer reports a refused file as loaded** (#824). The dock
  checks the file first, the way it does a `.map`, and a refusal shows the
  reason without touching undo history or recent files.
- **DEVELOPMENT.md explains the `inst_to_dict()` error from `assert_eq` on a
  shim-scripted node** (#805), with the error text to search for and the
  instance id comparison that avoids it.
- **Two comments stop saying only two `tools/` scripts can fail a build**
  (#819). `pyproject.toml` now gives those two as examples rather than a
  count, and the `ci.yml` comment is gone, since the step names below it are
  the list.
- **`--help` on the `tools/` scripts prints their usage lines as written**
  (#820). argparse's default formatter ran the indented invocations at the top
  of each docstring into one sentence. The nine parsers that print the whole
  docstring now use `RawDescriptionHelpFormatter`.
- **The release tree builder refuses to build into the repository, and a pull
  request now runs it** (#817). It took its destination as a bare positional
  path and checked only that the directory was empty, so a mistyped invocation
  built the whole tree inside the working tree. `--selftest`, typed on the
  assumption that this script carried the flag most of `tools/` does, was read
  as the destination: 855 files into a directory of that name in the repository
  root, exit 0, and the next `git add -A` swept them into a commit. Arguments go
  through argparse now, so an unknown flag is an error rather than a
  destination, and a path under the repository root is refused with a line
  saying why. The script also has the `--selftest` it was assumed to have: it
  builds into a temporary directory and checks that the root holds what `SHIP`
  says and the two generated files, that nothing in `EXCLUDED_ON_PURPOSE` got
  in, and that the destination guard still turns the repository down. CI runs it
  on every pull request. This script decides what reaches the Asset Library and
  it ran in exactly one place, on the tag, so the earliest anyone found out it
  was broken was the release.
- **The full release zip stops carrying two READMEs** (#789). `hammerforge-<version>.zip`
  had a generated `README.md` at its root and the committed
  `addons/hammerforge/README.md` inside it, and both told a reader what
  HammerForge is and how to enable it. One is a string literal in a build script
  and the other is a Markdown file in the plugin folder, so editing either did
  nothing to the other, and on day one they already disagreed about the wording
  of every line they shared. The generated one now says only what is true of the
  *tree*: that this is a release tree rather than a project, where to copy
  `addons/hammerforge` to, that the release page carries a plugin-only zip, and
  that `addons/hammerforge/README.md` describes the plugin. The selftest above
  fails if it stops pointing there.
- **The wiring guard's selftest stops leaning on the tree it checks** (#813).
  `unrun_selftests()` walks `tools/` and reads a fixture workflow, and the
  fixture named two real scripts. So each of the two assertions about it had a
  second way to pass that had nothing to do with the flag they are there for.
  Dropping a step from the fixture left the check green with the property no
  longer tested, and renaming either script failed it with a message about a
  guard being run without its flag, which is not what happened. The fixture now
  gets a throwaway `tools/` of its own, two scripts written for the length of
  the check, and a line that fails when the fixture stops running the unwired
  one. No rename in `tools/` can reach it, and every message it prints means
  what it says.
- **A redirected local run keeps each check's output under its step** (#808).
  `python tools/run_local_checks.py` prints a header and the command for each
  check, then hands its own stdout to the child. Python block buffers stdout
  when it is not a terminal, so sending the run to a file put every check's
  output at the top, unlabelled and in one block, with every header and the
  summary after it. `| tail` then showed the step names and hid every reason,
  which is the half you need, and that is how the new uid note in #804 went
  unread while it was being written. Stdout is line buffered before the first
  child runs now. The runner's selftest drives a one-check run through a pipe
  and fails if the child's output lands above the header that announced it, and
  CI runs that selftest: the local runner was the only guard in that job whose
  own selftest nothing ran.
- **The CI section stops counting the lint guards** (#809). It said the first
  job runs nine Python scripts, four of them checks on the tree and the other
  five selftests. The job runs ten. The tenth is `run_local_checks.py --check`,
  which is neither: it reads `ci.yml` and fails when a step of either lint job
  is not accounted for locally. The sentence was wrong on the commit that wrote
  it, which is the commit that added that guard, so the one thing keeping the
  page and `ci.yml` together is the thing the page left out. Both counts in that
  section are gone rather than corrected. A number in prose is what went stale,
  and the step names inside the job are the accurate list.
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
- **A primitive keeps its face materials when its sides change** (#851).
  Changing `sides` on a placed cylinder, cone or pyramid dropped every face's
  material, UV settings, paint and sculpt, and setting it back brought nothing
  back. Each new face now takes the look of the old face that faced its way. A
  sculpt or custom UVs only go to a face with the same corners, and what cannot
  follow is dropped with a warning naming the brush. A shape change works the
  same way.
- **Resizing a sphere, ellipsoid or torus is about twenty times faster**
  (#852). Each resize turned a mesh of a few thousand triangles back into
  faces, over 100 ms, so dragging a resize handle updated six to nine times a
  second. Their faces are now built once and scaled. They are also the same
  faces at every size: rounding split a few flat quads into triangles at some
  sizes, so a resize could change a sphere's face count.
- **A capsule has the same faces at every size** (#858). Turning its mesh into
  faces rounded each plane's distance at a fixed step, so on a large capsule
  some flat quads stayed two triangles: 2,432 faces at 32 units, 2,500 at
  1,000. Triangles are now grouped by the way they face, and joined only where
  they share an edge, as before.
- **Flip's fallback for a sculpted primitive has a test** (#849). When a
  box's faces cannot be paired across the mirror, a sculpt is what makes Flip
  bake the brush into its faces and mirror the sculpt with it. Nothing checked
  that, so it could break unseen.

### Added
- **CI is checked for guards it never runs** (#811). `run_local_checks.py
  --check` read `ci.yml` and asked whether everything CI runs was accounted for
  locally. It never asked the other direction, so a script could carry a
  `--selftest` that no step ran and every check stayed green. That is not
  hypothetical: the runner shipped its own selftest in #794 and nothing ran it
  until #810. A selftest nobody runs is worse than none, because it reads as
  covered in a review and can rot into passing on a fixture whose shape has
  moved on. `--check` now walks `tools/` for scripts that accept the flag and
  fails when `ci.yml` has no step passing it to one. The flag is found by
  parsing the file rather than by grepping it, so a script that only mentions
  `--selftest` in a comment or an error message does not land on a list it
  could never get off.
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
- **DEVELOPMENT.md stops describing a carve UV fix that no longer exists**
  (#859). Its note named `_copy_uv_settings_to_piece()`, which went when Carve
  moved onto `HFConvexClip`. It now says why a cut piece keeps its alignment,
  and that a face's look is copied through `FaceData.copy_appearance_from()`.
  The user guide's Clip and Carve section says a `.map` texture name survives a
  cut and that paint and sculpts do not yet (#863).
- **The data portability notes cover sculpts and round shapes in the scene**
  (#854, #852, #858). A sculpt is saved with the scene now, and a build from
  before that reads one but drops it on its next save. A sphere, ellipsoid,
  torus or capsule saved where rounding had split some quads opens with them
  whole and keeps its look. The smoke checklist gains manual checks for #844,
  #851, #852 and #854.
- **The docs say Test Level builds entity nodes, like the exports** (#840).
  The user guide's entity reference, its Test Level steps, the data
  portability notes and the smoke checklist's timer check all cover Test
  Level. The shipping guide says an exported timer starts on load, the data
  portability notes say a missing property exports at its default, and the
  test tables describe what `test_export_playtest.gd` covers now.
- **CONTRIBUTING.md says where the counts commit comes from and what it needs.**
  It claimed CI rewrites the published totals on a push to `main`; it does so
  on pull requests, and `main` only reports drift. It now also names the deploy
  key the push depends on, what a missing one looks like, and why a re-run
  after three days has to be a full one. The editor smoke checklist gains manual
  checks for #822, #823, #824, #826 and #827.
- **Two finished plans still read as work orders** (#815).
  `docs/superpowers/plans/` holds the CI sharding plan and the core-loop
  freeze plan. Both shipped, and both still opened with a line telling an
  agentic worker to pick the plan up and implement it, the sharding one with
  28 unticked boxes under it. Anyone who followed either header would rebuild
  something that already runs on every push. Both now open with the release
  they shipped in and a line saying not to implement them again, and the 28
  boxes are ticked. One of the sharding plan's constraints was also wrong: it
  said a new script must be a direct child of `tools/` to be linted at all,
  and ruff already lints `tools/vibe/run_vibe.py`, because ruff matches
  `include` with globset and there `*` crosses `/`. That sentence and the
  comment above `include` in `pyproject.toml` both say so now, so the next
  reader of either does not reach the same wrong conclusion. The plan's file
  table also named `docs/patterns_and_gotchas.md`, which does not exist here.
  The `-gconfig=` note it describes went into `DEVELOPMENT.md`.
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
