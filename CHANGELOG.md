# Changelog

What changed in HammerForge, newest first. Each release opens with its
highlights and then lists its changes week by week. Every line gives the day
the change merged, says what changed, and links the issue it closed and the
pull request that made it. The pull request has the detail.

- **Added**: something new to use.
- **Changed**: something that works differently now.
- **Deprecated**: something that still works but is going away.
- **Removed**: something that is gone.
- **Fixed**: a bug that is gone.
- **Security**: a vulnerability that is closed.
- **Behind the scenes**: tests, CI, tooling, docs and code moves you will not
  notice in the editor.

Until 5 October 2026 each entry was a long write-up. Those are kept word for
word in [changelog/](changelog/), one file per release.

## At a glance

| Release | Released | Work dates | Added | Changed | Removed | Fixed | Behind the scenes | Total |
|---|---|---|---|---|---|---|---|---|
| 0.3.2 | 19 Sep 2026 | 5 to 19 Sep 2026 | 36 | 30 | 2 | 247 | 54 | 370 |
| 0.3.0 | 3 Sep 2026 | 10 Apr to 3 Sep 2026 | 15 | 13 | 0 | 30 | 27 | 85 |
| 0.2.0 | 9 Apr 2026 | 6 Feb to 9 Apr 2026 | 86 | 21 | 0 | 58 | 56 | 221 |
| 0.1.1 | 5 Feb 2026 | 5 Feb 2026 | 2 | 3 | 0 | 2 | 4 | 11 |
| 0.1.0 | 5 Feb 2026 | 30 Jan to 5 Feb 2026 | 37 | 3 | 0 | 8 | 7 | 55 |

Unreleased work is counted when it ships. For the numbers so far, run
`python tools/check_changelog.py --summary`.

## [Unreleased]

**Highlights so far**

- Textures sit right: walls and cylinders were drawn upside down, `.map` files carry texture alignment in texels both ways, and Valve 220 exports keep a face's rotation.
- Cuts keep their looks: Clip, Carve and Hollow keep paint, sculpts and Cylindrical UVs, and Ctrl+S saves sculpts with the scene.
- The viewport behaves: one key press runs once, autosave survives a scene tab switch, and a click in a scene that is not a level leaves it alone.
- Test Level runs entities the way an exported game does, so timers fire, lights light and `func_wall` answers Enable and Disable.
- Behind the scenes, tests build real levels instead of sixty stand-ins, and CI fails a run that ends with orphans or warnings.

The long write-ups for these, as first written: [changelog/after-0.3.2.md](changelog/after-0.3.2.md)

### Week of 5 Oct 2026

#### Added

- **9 Oct** A level can hold several cordons at once; a partial bake takes every brush in any of them, so two rooms bake without the corridor between. (PR [#966](https://github.com/saworbit/hammerforge/pull/966))

#### Fixed

- **9 Oct** The spawn Test Level makes stands on the top of the floor; on a floor thicker than 0.2 it warned about its own spawn, or stopped with it inside the floor. (issue [#961](https://github.com/saworbit/hammerforge/issues/961))

#### Behind the scenes

- **9 Oct** A pull request that changes the docs site builds it first, so a broken link fails there; one merged clean and kept the site from deploying for four days. (PR [#965](https://github.com/saworbit/hammerforge/pull/965))
- **8 Oct** The docs site deploys again; a link from the features page to CONTRIBUTING.md had failed every build since 4 Oct. (PR [#964](https://github.com/saworbit/hammerforge/pull/964))
- **5 Oct** The stand-in guard refuses a test-built script made from anything but one triple-quoted block; two stand-ins had hidden as joined strings. (issue [#957](https://github.com/saworbit/hammerforge/issues/957), PR [#960](https://github.com/saworbit/hammerforge/pull/960))
- **5 Oct** CI checks that every level member a vibe harness scenario calls really exists; two scenarios had been quietly skipping their own question. (issue [#958](https://github.com/saworbit/hammerforge/issues/958), PR [#960](https://github.com/saworbit/hammerforge/pull/960))
- **5 Oct** The brush change tracker calls the level's members directly and drops its branches for a root that is not a LevelRoot. (issue [#952](https://github.com/saworbit/hammerforge/issues/952), PR [#956](https://github.com/saworbit/hammerforge/pull/956))
- **5 Oct** CI loads every vibe harness script and fails if one does not parse; a scenario calling a removed function had stayed green. (issue [#955](https://github.com/saworbit/hammerforge/issues/955), PR [#956](https://github.com/saworbit/hammerforge/pull/956))
- **5 Oct** The stand-in guard also refuses a test-built script that copies the level's enums or saved settings, and three more test files use a real LevelRoot. (issue [#951](https://github.com/saworbit/hammerforge/issues/951), PR [#956](https://github.com/saworbit/hammerforge/pull/956))

### Week of 28 Sep 2026

#### Added

- **3 Oct** Clip, Carve and Hollow confirmations warn when a sculpt cannot follow the cut and will be dropped. (issue [#871](https://github.com/saworbit/hammerforge/issues/871), PR [#890](https://github.com/saworbit/hammerforge/pull/890))
- **2 Oct** Flip mirrors a sculpted displacement instead of refusing the brush; removing a negative scale no longer leaves a sculpted brush to bake inside out. (PR [#847](https://github.com/saworbit/hammerforge/pull/847))

#### Changed

- **3 Oct** Resizing a capsule is cheap enough to drag: 3.9 to 6.5 ms per resize instead of 78 to 91 ms. (issue [#860](https://github.com/saworbit/hammerforge/issues/860), PR [#891](https://github.com/saworbit/hammerforge/pull/891))
- **2 Oct** Resizing a sphere, ellipsoid or torus is about twenty times faster, and keeps the same face count at every size. (issue [#852](https://github.com/saworbit/hammerforge/issues/852), PR [#856](https://github.com/saworbit/hammerforge/pull/856))

#### Fixed

- **4 Oct** Check Only reports a cut that only overlaps a door; validation counted the door as solid, so a cut that carved nothing went unreported. (issue [#942](https://github.com/saworbit/hammerforge/issues/942), PR [#944](https://github.com/saworbit/hammerforge/pull/944))
- **4 Oct** A click in a scene that is not a level leaves it alone; one Draw click in a player scene used to add a LevelRoot to it. (issue [#932](https://github.com/saworbit/hammerforge/issues/932), PR [#938](https://github.com/saworbit/hammerforge/pull/938))
- **4 Oct** An Entity panel edit is an undo step; Ctrl+Z used to undo the step before it, and could remove a freshly created entity. (issue [#931](https://github.com/saworbit/hammerforge/issues/931), PR [#938](https://github.com/saworbit/hammerforge/pull/938))
- **4 Oct** Brush presets survive an addon upgrade; they live in `res://hammerforge_presets/`, and an upgrade used to delete every one. (issue [#930](https://github.com/saworbit/hammerforge/issues/930), PR [#937](https://github.com/saworbit/hammerforge/pull/937))
- **4 Oct** A prefab save asks before it replaces a file; a second box's Quick Save used to overwrite the first box's prefab and its linked instances. (issue [#929](https://github.com/saworbit/hammerforge/issues/929), PR [#936](https://github.com/saworbit/hammerforge/pull/936))
- **4 Oct** Autosave keeps running after you switch scene tabs; one switch used to stop it for the rest of the session. (issue [#928](https://github.com/saworbit/hammerforge/issues/928), PR [#935](https://github.com/saworbit/hammerforge/pull/935))
- **4 Oct** One key press in the viewport runs once; Ctrl+D used to make two duplicates and Ctrl+V also pasted Godot's clipboard. (issue [#927](https://github.com/saworbit/hammerforge/issues/927), PR [#934](https://github.com/saworbit/hammerforge/pull/934))
- **4 Oct** A door stays open for its whole wait; a door slower to open than its wait used to turn back half way. (issue [#910](https://github.com/saworbit/hammerforge/issues/910), PR [#914](https://github.com/saworbit/hammerforge/pull/914))
- **4 Oct** The shortcut dialog lists Rotate, Flip and Reset Rotation, which had bindings but no row. (issue [#906](https://github.com/saworbit/hammerforge/issues/906), PR [#914](https://github.com/saworbit/hammerforge/pull/914))
- **4 Oct** Wall textures stand the right way up in the viewport and the bake; faces aligned or painted by hand in older levels keep their look. (issue [#907](https://github.com/saworbit/hammerforge/issues/907), PR [#913](https://github.com/saworbit/hammerforge/pull/913))
- **4 Oct** A wedge, cylinder or cut brush imported from a `.map` is textured properly; its floors and east and west walls showed one line of the texture. (issue [#909](https://github.com/saworbit/hammerforge/issues/909), PR [#912](https://github.com/saworbit/hammerforge/pull/912))
- **4 Oct** A turned brush converts to a heightmap and previews its cut over the right ground. (issue [#901](https://github.com/saworbit/hammerforge/issues/901), PR [#911](https://github.com/saworbit/hammerforge/pull/911))
- **4 Oct** A rotated face keeps its rotation in a Valve 220 export; other editors used to open every rotated face unrotated. (issue [#899](https://github.com/saworbit/hammerforge/issues/899), PR [#908](https://github.com/saworbit/hammerforge/pull/908))
- **4 Oct** A `.map` face's texture scale and offset are written and read in texels; a 64 pixel texture used to open 64 times too large elsewhere. (issue [#894](https://github.com/saworbit/hammerforge/issues/894), PR [#898](https://github.com/saworbit/hammerforge/pull/898))
- **4 Oct** Similar Faces and Similar Brushes select the same things from the command and the Selection Filters popover, and leave hidden brushes out. (issues [#896](https://github.com/saworbit/hammerforge/issues/896), [#897](https://github.com/saworbit/hammerforge/issues/897), PR [#898](https://github.com/saworbit/hammerforge/pull/898))
- **4 Oct** The Valve 220 export writes the Box UV axis the viewport draws; a box turned exactly 45 degrees could export faces textured differently. (issue [#895](https://github.com/saworbit/hammerforge/issues/895), PR [#898](https://github.com/saworbit/hammerforge/pull/898))
- **3 Oct** Box UV projects a stretched slope along the axis it really faces; a slope on a stretched wedge used to be textured about four times too long. (issue [#887](https://github.com/saworbit/hammerforge/issues/887), PR [#892](https://github.com/saworbit/hammerforge/pull/892))
- **3 Oct** A hollow or a flight made before the face-order fix reads correctly after a reopen, instead of every wall and step counting as edited. (issue [#878](https://github.com/saworbit/hammerforge/issues/878), PR [#891](https://github.com/saworbit/hammerforge/pull/891))
- **3 Oct** Update Array asks before it rebuilds over a paint stroke on a copy; the first press used to rebuild over it without a word. (issue [#875](https://github.com/saworbit/hammerforge/issues/875), PR [#891](https://github.com/saworbit/hammerforge/pull/891))
- **3 Oct** A cut keeps Cylindrical UVs, and the paint on them, where they were; Clip, Carve and Hollow used to turn and stretch the texture. (issue [#868](https://github.com/saworbit/hammerforge/issues/868), PR [#890](https://github.com/saworbit/hammerforge/pull/890))
- **3 Oct** Bevel and Inset keep a sculpt on the surface it was on instead of squeezing the whole grid onto the smaller face. (issue [#870](https://github.com/saworbit/hammerforge/issues/870), PR [#890](https://github.com/saworbit/hammerforge/pull/890))
- **3 Oct** Flip judges whether a box's faces look alike the way the rest of the editor does, so a face with custom UVs counts as a different look. (issue [#864](https://github.com/saworbit/hammerforge/issues/864), PR [#890](https://github.com/saworbit/hammerforge/pull/890))
- **3 Oct** A stretched brush bakes its slopes lit the way they face; normals on a stretched cylinder used to lean up to 60 degrees off. (issue [#884](https://github.com/saworbit/hammerforge/issues/884), PR [#888](https://github.com/saworbit/hammerforge/pull/888))
- **3 Oct** A `.map` HammerForge exported brings back each face's texture alignment; import used to drop every face's offset, scale and rotation. (issue [#885](https://github.com/saworbit/hammerforge/issues/885), PR [#888](https://github.com/saworbit/hammerforge/pull/888))
- **3 Oct** A sculpt stroke in the viewport reaches the face; Raise, Lower, Smooth, Noise and Alpha used to do nothing there. (PR [#888](https://github.com/saworbit/hammerforge/pull/888))
- **3 Oct** A cylinder's `.map` export puts each texture on its own side, and a 5, 6 or 7 sided cylinder no longer exports turned. (issue [#880](https://github.com/saworbit/hammerforge/issues/880), PR [#883](https://github.com/saworbit/hammerforge/pull/883))
- **3 Oct** Reopening a scene no longer reads a hollow or a flight of stairs as reworked; Update used to move each step face's paint to another side. (issues [#873](https://github.com/saworbit/hammerforge/issues/873), [#867](https://github.com/saworbit/hammerforge/issues/867), PR [#879](https://github.com/saworbit/hammerforge/pull/879))
- **3 Oct** Re-hollow counts a paint stroke on a wall of a painted solid; it used to put the solid's paint back over the stroke without warning. (issue [#869](https://github.com/saworbit/hammerforge/issues/869), PR [#874](https://github.com/saworbit/hammerforge/pull/874))
- **2 Oct** Clip, Carve and Hollow keep surface paint and sculpts; carving a doorway through a finished wall used to wipe its paint. (issue [#863](https://github.com/saworbit/hammerforge/issues/863), PR [#866](https://github.com/saworbit/hammerforge/pull/866))
- **2 Oct** A clipped box keeps each face's texture through a resize and a reopen; the first resize used to move most textures to other faces. (PR [#866](https://github.com/saworbit/hammerforge/pull/866))
- **2 Oct** A face keeps its `.map` texture name through a rebuild, a duplicate and a cut, so an imported trigger box stays a trigger. (issue [#859](https://github.com/saworbit/hammerforge/issues/859), PR [#862](https://github.com/saworbit/hammerforge/pull/862))
- **2 Oct** An entity scene can have any root, and a refused one no longer leaks once per entity on every export and Test Level run. (issue [#844](https://github.com/saworbit/hammerforge/issues/844), PR [#857](https://github.com/saworbit/hammerforge/pull/857))
- **2 Oct** A primitive keeps its face materials when its sides change; changing a cylinder, cone or pyramid's sides used to drop them all. (issue [#851](https://github.com/saworbit/hammerforge/issues/851), PR [#856](https://github.com/saworbit/hammerforge/pull/856))
- **2 Oct** A capsule has the same faces at every size; a large one used to keep some flat quads split into two triangles. (issue [#858](https://github.com/saworbit/hammerforge/issues/858), PR [#856](https://github.com/saworbit/hammerforge/pull/856))
- **2 Oct** A sculpt is saved with the scene; Ctrl+S used to drop every displacement, so the scene reopened flat. (issue [#854](https://github.com/saworbit/hammerforge/issues/854), PR [#855](https://github.com/saworbit/hammerforge/pull/855))
- **2 Oct** A resize keeps a sculpt on a face saved with turned corners; the sculpt and its custom UVs used to turn half a turn. (issue [#846](https://github.com/saworbit/hammerforge/issues/846), PR [#850](https://github.com/saworbit/hammerforge/pull/850))
- **2 Oct** A displaced face is wound the way its face is; every sculpt used to face into its brush and be culled from outside. (issue [#845](https://github.com/saworbit/hammerforge/issues/845), PR [#847](https://github.com/saworbit/hammerforge/pull/847))
- **1 Oct** Test Level runs the node each entity class names, so a `logic_timer` fires and a light lights; both used to stay editor markers. (issue [#840](https://github.com/saworbit/hammerforge/issues/840), PR [#842](https://github.com/saworbit/hammerforge/pull/842))
- **1 Oct** The plugin loads in a project that turns on warnings for addons; the brush gizmo, paint tools and validation used to fail to load. (issue [#836](https://github.com/saworbit/hammerforge/issues/836), PR [#839](https://github.com/saworbit/hammerforge/pull/839))
- **1 Oct** A `logic_timer` starts when the level loads, set by the new Start On Load property; one wired only by `OnTimer` never fired. (issue [#835](https://github.com/saworbit/hammerforge/issues/835), PR [#838](https://github.com/saworbit/hammerforge/pull/838))
- **1 Oct** `func_wall` stays out of the world bake and answers Enable and Disable; a wire to it used to find nothing. (issue [#827](https://github.com/saworbit/hammerforge/issues/827), PR [#832](https://github.com/saworbit/hammerforge/pull/832))
- **1 Oct** Rewiring no longer lets a `trigger_once` volume or a fire once connection fire again. (issue [#825](https://github.com/saworbit/hammerforge/issues/825), PR [#832](https://github.com/saworbit/hammerforge/pull/832))
- **1 Oct** `logic_timer` exports as a `Timer` and fires `OnTimer`, and a definition can map an output to an engine signal with `output_signals`. (issue [#826](https://github.com/saworbit/hammerforge/issues/826), PR [#831](https://github.com/saworbit/hammerforge/pull/831))
- **1 Oct** Play from Camera and Play Selected Area no longer save their temporary spawn or cordon into the scene. (issue [#822](https://github.com/saworbit/hammerforge/issues/822), PR [#830](https://github.com/saworbit/hammerforge/pull/830))
- **1 Oct** A refused `.hflevel` no longer moves streamed paint; the open level's paint used to be written into the refused file's sidecar. (issue [#823](https://github.com/saworbit/hammerforge/issues/823), PR [#829](https://github.com/saworbit/hammerforge/pull/829))
- **1 Oct** Load .hflevel no longer reports a refused file as loaded, and shows the reason without touching undo history or recent files. (issue [#824](https://github.com/saworbit/hammerforge/issues/824), PR [#829](https://github.com/saworbit/hammerforge/pull/829))

#### Behind the scenes

- **4 Oct** The brush change tracker's tests run on a real level with real brushes, so the level's dirty tags and structure repair run under them. (issue [#948](https://github.com/saworbit/hammerforge/issues/948), PR [#950](https://github.com/saworbit/hammerforge/pull/950))
- **4 Oct** The last three test classes that copied LevelRoot members use the real class, and the stand-in guard refuses copied enums and saved settings. (issue [#946](https://github.com/saworbit/hammerforge/issues/946), PR [#949](https://github.com/saworbit/hammerforge/pull/949))
- **4 Oct** Systems call the level's dirty tags and settings directly, so a missing member is an error rather than a quiet skip. (issue [#945](https://github.com/saworbit/hammerforge/issues/945), PR [#949](https://github.com/saworbit/hammerforge/pull/949))
- **4 Oct** Tests build their levels from the real LevelRoot instead of sixty hand-written stand-ins that had drifted from it. (issue [#922](https://github.com/saworbit/hammerforge/issues/922), PR [#943](https://github.com/saworbit/hammerforge/pull/943))
- **4 Oct** CI packs the test shards by each script's measured time, so shards finish close together and a failing shard names its failing tests. (issue [#920](https://github.com/saworbit/hammerforge/issues/920), PR [#940](https://github.com/saworbit/hammerforge/pull/940))
- **4 Oct** CI fails when a test run ends with orphans or warnings, and names the script and test responsible. (issue [#923](https://github.com/saworbit/hammerforge/issues/923), PR [#939](https://github.com/saworbit/hammerforge/pull/939))
- **4 Oct** CONTRIBUTING gives one numbered test setup for a fresh clone and says the import is required, or GUT runs nothing and exits 0. (issue [#924](https://github.com/saworbit/hammerforge/issues/924), PR [#939](https://github.com/saworbit/hammerforge/pull/939))
- **4 Oct** The VS Code test tasks run one file instead of the whole suite, exit when done, and link script errors without flooding the Problems panel. (issue [#925](https://github.com/saworbit/hammerforge/issues/925), PR [#939](https://github.com/saworbit/hammerforge/pull/939))
- **4 Oct** CI no longer commits test counts to a pull request; the totals refresh when a release is cut, and the static tests badge is gone. (issue [#916](https://github.com/saworbit/hammerforge/issues/916), PR [#933](https://github.com/saworbit/hammerforge/pull/933))
- **4 Oct** Dependabot waits seven days before proposing a release, and the zizmor audit also reads `.github/dependabot.yml`. (issue [#918](https://github.com/saworbit/hammerforge/issues/918), PR [#933](https://github.com/saworbit/hammerforge/pull/933))
- **4 Oct** The release workflow refuses a tag that does not match `plugin.cfg` and pushes the `release` branch last; a run started by hand is a dry run. (issue [#919](https://github.com/saworbit/hammerforge/issues/919), PR [#933](https://github.com/saworbit/hammerforge/pull/933))
- **4 Oct** The path, polygon and measure tools share one overlay builder; the shortcut lists and paint chunk packing each use one shared helper. (issues [#904](https://github.com/saworbit/hammerforge/issues/904), [#906](https://github.com/saworbit/hammerforge/issues/906), [#900](https://github.com/saworbit/hammerforge/issues/900), PR [#914](https://github.com/saworbit/hammerforge/pull/914))
- **4 Oct** The brush preview resolves face materials the way the bake does, and validation walks baked meshes with the bake's own collector. (issues [#902](https://github.com/saworbit/hammerforge/issues/902), [#903](https://github.com/saworbit/hammerforge/issues/903), PR [#911](https://github.com/saworbit/hammerforge/pull/911))
- **4 Oct** Both `.map` adapters write offsets, rotations and axes through one shared number formatter. (issue [#905](https://github.com/saworbit/hammerforge/issues/905), PR [#908](https://github.com/saworbit/hammerforge/pull/908))
- **3 Oct** `tools/wait_for_ci.py` reads an all-digit short SHA of seven digits or more as a commit, not a pull request number. (issue [#876](https://github.com/saworbit/hammerforge/issues/876), PR [#889](https://github.com/saworbit/hammerforge/pull/889))
- **3 Oct** A full test run prints no warnings or deprecations. (issue [#882](https://github.com/saworbit/hammerforge/issues/882), PR [#889](https://github.com/saworbit/hammerforge/pull/889))
- **2 Oct** DEVELOPMENT.md stops describing a removed carve UV fix, and the user guide says a cut keeps a `.map` texture name but not yet paint. (issues [#859](https://github.com/saworbit/hammerforge/issues/859), [#863](https://github.com/saworbit/hammerforge/issues/863), PR [#865](https://github.com/saworbit/hammerforge/pull/865))
- **2 Oct** The data portability notes cover sculpts saved with the scene and round shapes whose split quads reopen whole. (issues [#854](https://github.com/saworbit/hammerforge/issues/854), [#852](https://github.com/saworbit/hammerforge/issues/852), [#858](https://github.com/saworbit/hammerforge/issues/858), PR [#861](https://github.com/saworbit/hammerforge/pull/861))
- **2 Oct** Flip's fallback for a sculpted primitive has a test. (issue [#849](https://github.com/saworbit/hammerforge/issues/849), PR [#856](https://github.com/saworbit/hammerforge/pull/856))
- **2 Oct** The docs say Test Level builds entity nodes, like the exports, and that an exported timer starts on load. (issue [#840](https://github.com/saworbit/hammerforge/issues/840), PR [#843](https://github.com/saworbit/hammerforge/pull/843))
- **1 Oct** DEVELOPMENT.md and the spec no longer list a test count per file; about half of those hand-kept numbers had drifted. (issue [#837](https://github.com/saworbit/hammerforge/issues/837), PR [#839](https://github.com/saworbit/hammerforge/pull/839))
- **1 Oct** CONTRIBUTING.md says the counts commit is pushed on pull requests, not on `main`, and names the deploy key it depends on. (PR [#834](https://github.com/saworbit/hammerforge/pull/834))
- **1 Oct** DEVELOPMENT.md explains the `inst_to_dict()` error from `assert_eq` on a shim-scripted node and how to avoid it. (issue [#805](https://github.com/saworbit/hammerforge/issues/805), PR [#833](https://github.com/saworbit/hammerforge/pull/833))
- **1 Oct** Two comments stop saying only two `tools/` scripts can fail a build. (issue [#819](https://github.com/saworbit/hammerforge/issues/819), PR [#833](https://github.com/saworbit/hammerforge/pull/833))
- **1 Oct** `--help` on the `tools/` scripts prints their usage lines as written instead of running them into one sentence. (issue [#820](https://github.com/saworbit/hammerforge/issues/820), PR [#833](https://github.com/saworbit/hammerforge/pull/833))

### Week of 14 Sep 2026

#### Added

- **20 Sep** Bake Check warns when a connector ramp is steeper than the navmesh agent can walk, naming the steepest and the cell it starts from. (issue [#798](https://github.com/saworbit/hammerforge/issues/798), PR [#800](https://github.com/saworbit/hammerforge/pull/800))
- **20 Sep** Every nav bake reports its source and polygon count in the Console, and an empty navmesh region is a warning that says why. (issue [#788](https://github.com/saworbit/hammerforge/issues/788), PR [#797](https://github.com/saworbit/hammerforge/pull/797))
- **20 Sep** The plugin folder explains itself: a README covers enabling it, a first level, and that replacing the folder deletes what you put in it. (issue [#780](https://github.com/saworbit/hammerforge/issues/780), PR [#785](https://github.com/saworbit/hammerforge/pull/785))

#### Fixed

- **20 Sep** Bake Check reads the connector mode before it warns about stairs; it used to warn in Ramp mode and miss stairs placed by hand. (issue [#802](https://github.com/saworbit/hammerforge/issues/802), PR [#806](https://github.com/saworbit/hammerforge/pull/806))

#### Behind the scenes

- **20 Sep** The release tree builder refuses to build into the repository, gains a `--selftest`, and runs on every pull request. (issue [#817](https://github.com/saworbit/hammerforge/issues/817), PR [#818](https://github.com/saworbit/hammerforge/pull/818))
- **20 Sep** The full release zip stops carrying two READMEs; its generated one only describes the tree and points at the plugin's own README. (issue [#789](https://github.com/saworbit/hammerforge/issues/789), PR [#818](https://github.com/saworbit/hammerforge/pull/818))
- **20 Sep** Two finished plans no longer read as work orders: each names the release it shipped in and says not to implement it again. (issue [#815](https://github.com/saworbit/hammerforge/issues/815), PR [#816](https://github.com/saworbit/hammerforge/pull/816))
- **20 Sep** The wiring guard's selftest uses a throwaway `tools/` of its own, so no rename in the real tree can make it pass or fail wrongly. (issue [#813](https://github.com/saworbit/hammerforge/issues/813), PR [#814](https://github.com/saworbit/hammerforge/pull/814))
- **20 Sep** `run_local_checks.py --check` fails when a `tools/` script has a `--selftest` that no CI step runs. (issue [#811](https://github.com/saworbit/hammerforge/issues/811), PR [#812](https://github.com/saworbit/hammerforge/pull/812))
- **20 Sep** A redirected `tools/run_local_checks.py` run keeps each check's output under its own header, and CI runs the runner's selftest. (issue [#808](https://github.com/saworbit/hammerforge/issues/808), PR [#810](https://github.com/saworbit/hammerforge/pull/810))
- **20 Sep** The docs' CI section stops counting the lint guards; its count was wrong, and the step names in `ci.yml` are the list. (issue [#809](https://github.com/saworbit/hammerforge/issues/809), PR [#810](https://github.com/saworbit/hammerforge/pull/810))
- **20 Sep** The uid check lists untracked sources under its verdict and marks those with no id, which fail once staged. (issue [#804](https://github.com/saworbit/hammerforge/issues/804), PR [#807](https://github.com/saworbit/hammerforge/pull/807))
- **20 Sep** The stairs half of the Bake Check has tests, including the boundary where a default project must not be warned. (issue [#801](https://github.com/saworbit/hammerforge/issues/801), PR [#803](https://github.com/saworbit/hammerforge/pull/803))
- **20 Sep** ROADMAP drops a hand-written claim that no issues were open while issues were open. (issue [#799](https://github.com/saworbit/hammerforge/issues/799), PR [#803](https://github.com/saworbit/hammerforge/pull/803))
- **20 Sep** The User Guide gives Stair Threshold's default as 2.0, not the old Quake-scale 32.0. (PR [#800](https://github.com/saworbit/hammerforge/pull/800))
- **20 Sep** `tools/check_project_settings.py` gives the same answer as CI when `project.godot` is marked skip-worktree locally. (issue [#795](https://github.com/saworbit/hammerforge/issues/795), PR [#796](https://github.com/saworbit/hammerforge/pull/796))
- **20 Sep** `tools/run_local_checks.py` runs every check CI's lint jobs can fail you on, in one command. (issue [#792](https://github.com/saworbit/hammerforge/issues/792), PR [#794](https://github.com/saworbit/hammerforge/pull/794))
- **20 Sep** DEVELOPMENT.md warns that a cold `.godot` cache invents parse errors and says to confirm any of them headlessly first. (issue [#784](https://github.com/saworbit/hammerforge/issues/784), PR [#794](https://github.com/saworbit/hammerforge/pull/794))
- **20 Sep** DEVELOPMENT.md records why the first CI job keeps its formatting name: the branch ruleset requires it. (issue [#793](https://github.com/saworbit/hammerforge/issues/793), PR [#794](https://github.com/saworbit/hammerforge/pull/794))
- **20 Sep** `tools/check_uid_parity.py` fails when a tracked script has no `.uid` or a `.uid` has lost its script. (issue [#783](https://github.com/saworbit/hammerforge/issues/783), PR [#791](https://github.com/saworbit/hammerforge/pull/791))
- **20 Sep** The Asset Library check compares the entry's version with `plugin.cfg` and fails on a mislabelled entry. (issue [#790](https://github.com/saworbit/hammerforge/issues/790), PR [#791](https://github.com/saworbit/hammerforge/pull/791))
- **20 Sep** A weekly workflow fails when the Asset Library entry has served an old commit for over three days, allowing for queued edits. (issue [#778](https://github.com/saworbit/hammerforge/issues/778), PR [#787](https://github.com/saworbit/hammerforge/pull/787))
- **20 Sep** Drafted release notes name both download zips and which one most people want, and the install guide says where to get HammerForge. (issue [#779](https://github.com/saworbit/hammerforge/issues/779), PR [#785](https://github.com/saworbit/hammerforge/pull/785))

## [0.3.2] - 2026-09-19

**Highlights**

- One unit is one metre, and grid snap, the default brush and generator sizes all agree.
- Hollow, Clip and Carve work on any convex brush at any rotation with previews of the real cut, and a structure library builds arches, stairs, spiral stairs and domes you can Update in place.
- Levels you can ship: Export Game Scene, a Shipping a Level guide, doors, buttons, triggers and timers that work, and a reference map.
- The HammerForge Console opens beside 2D, 3D and Script, with Status, Controls and Log tabs.
- Hundreds of hardening fixes: a bad value in a file or setting is refused with a reason instead of damaging the level, and every dock command can be undone.

The long write-ups, as first written: [changelog/0.3.2.md](changelog/0.3.2.md)

### Week of 14 Sep 2026

#### Added

- **18 Sep** A reference map ships with the plugin: one `.hflevel` with materials, world UVs, visgroups, wired entities and bake options together. (issue [#710](https://github.com/saworbit/hammerforge/issues/710), PR [#756](https://github.com/saworbit/hammerforge/pull/756))
- **18 Sep** A cut's interior takes the cutter's texturing face by face, so a window reveal is textured by painting the cutter. (issue [#746](https://github.com/saworbit/hammerforge/issues/746), PR [#750](https://github.com/saworbit/hammerforge/pull/750))
- **18 Sep** A hit can name the surface it hit: the bake writes material names onto its collision and `HFSurface` looks them up from a ray. (issue [#707](https://github.com/saworbit/hammerforge/issues/707), PR [#745](https://github.com/saworbit/hammerforge/pull/745))
- **18 Sep** Validate reports two brushes in one level sharing an id, which left one of them unreachable by visgroups, groups and the Console. (issue [#696](https://github.com/saworbit/hammerforge/issues/696), PR [#741](https://github.com/saworbit/hammerforge/pull/741))
- **18 Sep** Ctrl+C and Ctrl+V copy and paste a selection, wiring and materials included, between levels and even between projects. (issue [#703](https://github.com/saworbit/hammerforge/issues/703), PR [#738](https://github.com/saworbit/hammerforge/pull/738))
- **18 Sep** A sound entity, ambient_sound, plays a 3D stream with Play and Stop inputs, so the Door Open -> Light + Sound preset can be filled. (issue [#704](https://github.com/saworbit/hammerforge/issues/704), PR [#729](https://github.com/saworbit/hammerforge/pull/729))
- **17 Sep** Validate reports two brushes in the same place, such as a Ctrl+D copy left on the original that causes z-fighting. (issue [#702](https://github.com/saworbit/hammerforge/issues/702), PR [#725](https://github.com/saworbit/hammerforge/pull/725))
- **17 Sep** Navmesh max climb and max slope can be set in the Manage tab, and Bake Check warns when stairs are out of every agent's reach. (issue [#701](https://github.com/saworbit/hammerforge/issues/701), PR [#724](https://github.com/saworbit/hammerforge/pull/724))
- **17 Sep** Export Game Scene writes a shippable scene with real entity nodes and no debug player, environment or sun. (issues [#697](https://github.com/saworbit/hammerforge/issues/697), [#698](https://github.com/saworbit/hammerforge/issues/698), PR [#722](https://github.com/saworbit/hammerforge/pull/722))
- **17 Sep** A Shipping a Level guide covers which files are the level, what export writes, baked lighting, bake options and raising outputs. (issue [#709](https://github.com/saworbit/hammerforge/issues/709), PR [#722](https://github.com/saworbit/hammerforge/pull/722))
- **17 Sep** `entities.json` ships fifteen entity classes instead of three, adding triggers, a button, spot and directional lights, relays and timers. (issue [#659](https://github.com/saworbit/hammerforge/issues/659), PR [#682](https://github.com/saworbit/hammerforge/pull/682))
- **17 Sep** The palette gains Clear and Remove Unused buttons; undoing Refresh Prototypes used to take 149 presses of the minus button. (issue [#661](https://github.com/saworbit/hammerforge/issues/661), PR [#678](https://github.com/saworbit/hammerforge/pull/678))
- **17 Sep** A level says when its `.hflevel` is newer than its `.tscn`, with a Console line and a toast when it is opened. (issue [#646](https://github.com/saworbit/hammerforge/issues/646), PR [#650](https://github.com/saworbit/hammerforge/pull/650))
- **17 Sep** A `.hflevel` records the scene it was saved from, so the newer-file warning ignores another level's file. (issue [#646](https://github.com/saworbit/hammerforge/issues/646), PR [#650](https://github.com/saworbit/hammerforge/pull/650))
- **17 Sep** Scene Keeps on the LevelRoot chooses what Ctrl+S writes to the `.tscn`: brushes and bake, brushes only, or baked geometry only. (issue [#624](https://github.com/saworbit/hammerforge/issues/624), PR [#645](https://github.com/saworbit/hammerforge/pull/645))
- **17 Sep** The dock can rename a visgroup, remove a prefab variant and change a displacement's power without throwing the sculpt away. (issue [#615](https://github.com/saworbit/hammerforge/issues/615), PR [#643](https://github.com/saworbit/hammerforge/pull/643))
- **16 Sep** Save Library and Load Library buttons are in the Paint tab, and saving warns about materials it cannot record. (issues [#498](https://github.com/saworbit/hammerforge/issues/498), [#515](https://github.com/saworbit/hammerforge/issues/515), PR [#535](https://github.com/saworbit/hammerforge/pull/535))

#### Changed

- **19 Sep** Nudging, rotating or flipping a selection with entities records only what moved for undo; each keypress used to snapshot the whole level. (issue [#761](https://github.com/saworbit/hammerforge/issues/761), PR [#767](https://github.com/saworbit/hammerforge/pull/767))
- **19 Sep** The UV spinboxes and a material dropped on a face record one brush for undo, not a whole-level snapshot per drag tick. (issue [#761](https://github.com/saworbit/hammerforge/issues/761), PR [#766](https://github.com/saworbit/hammerforge/pull/766))
- **18 Sep** Bevel, inset and the gizmo resize drag record only the brushes they change for undo, not a whole-level snapshot. (issue [#761](https://github.com/saworbit/hammerforge/issues/761), PR [#765](https://github.com/saworbit/hammerforge/pull/765))
- **18 Sep** Every displacement edit, the sculpt drag included, records only its brush for undo; a stroke used to snapshot the whole level twice. (issue [#761](https://github.com/saworbit/hammerforge/issues/761), PR [#762](https://github.com/saworbit/hammerforge/pull/762))
- **18 Sep** An undo step for nudge, rotate, flip or reset rotation is the size of the change, not a snapshot of the whole level. (issue [#737](https://github.com/saworbit/hammerforge/issues/737), PR [#760](https://github.com/saworbit/hammerforge/pull/760))
- **18 Sep** Undo stops repainting a level that did not change; Ctrl+Z on a 900-brush map drops from 195 ms to 51 ms. (issue [#705](https://github.com/saworbit/hammerforge/issues/705), PR [#736](https://github.com/saworbit/hammerforge/pull/736))
- **17 Sep** func_detail is the cheap option it reads like: detail brushes bake into one mesh per material and one body, not three nodes each. (issue [#712](https://github.com/saworbit/hammerforge/issues/712), PR [#723](https://github.com/saworbit/hammerforge/pull/723))
- **17 Sep** An uncompressed level is written one value per line in a stable key order, so it diffs and merges in version control. (issue [#708](https://github.com/saworbit/hammerforge/issues/708), PR [#717](https://github.com/saworbit/hammerforge/pull/717))
- **17 Sep** Undo is faster on large levels because unchanged brushes are kept rather than rebuilt; a 400-brush restore went from 122 ms to 44 ms. (issue [#600](https://github.com/saworbit/hammerforge/issues/600), PR [#642](https://github.com/saworbit/hammerforge/pull/642))
- **17 Sep** Saving and autosave stall the editor less; a 400-brush save blocks for 55 ms instead of 183 ms. (issue [#601](https://github.com/saworbit/hammerforge/issues/601), PR [#641](https://github.com/saworbit/hammerforge/pull/641))
- **17 Sep** One world unit is one metre and the drawing defaults agree: grid snap 0.5, a 2 x 2 x 2 default brush and walkable generator sizes. (issue [#625](https://github.com/saworbit/hammerforge/issues/625), PR [#638](https://github.com/saworbit/hammerforge/pull/638))
- **16 Sep** A click in face mode no longer rebuilds the preview of every brush in the level, which it did for a value nothing read. (issue [#563](https://github.com/saworbit/hammerforge/issues/563), PR [#584](https://github.com/saworbit/hammerforge/pull/584))

#### Removed

- **18 Sep** The Use MultiMesh bake toggle is gone; it could never consolidate anything a bake produces. (issue [#692](https://github.com/saworbit/hammerforge/issues/692), PR [#743](https://github.com/saworbit/hammerforge/pull/743))
- **17 Sep** `DraftEntity.entity_properties` and `LevelRoot.drag_active` are gone, along with fifty-seven private functions nothing used. (issues [#609](https://github.com/saworbit/hammerforge/issues/609), [#610](https://github.com/saworbit/hammerforge/issues/610), PR [#644](https://github.com/saworbit/hammerforge/pull/644))

#### Fixed

- **19 Sep** Test Level starts a level with a player in it again; the window used to come up flat grey, with no player and no camera. (issue [#771](https://github.com/saworbit/hammerforge/issues/771), PR [#770](https://github.com/saworbit/hammerforge/pull/770))
- **19 Sep** Redo of Create Starter Level brings the player spawn back; saving after an undo and redo used to write a scene with no brushes or spawn. (issue [#772](https://github.com/saworbit/hammerforge/issues/772), PR [#770](https://github.com/saworbit/hammerforge/pull/770))
- **19 Sep** The Bake row says how long the bake took, as in Bake complete in 340 ms, and is coloured as a success. (issue [#773](https://github.com/saworbit/hammerforge/issues/773), PR [#770](https://github.com/saworbit/hammerforge/pull/770))
- **19 Sep** A new level no longer arrives with a warning on it; every level used to carry a yellow triangle in the Scene dock. (issue [#774](https://github.com/saworbit/hammerforge/issues/774), PR [#770](https://github.com/saworbit/hammerforge/pull/770))
- **19 Sep** A material dropped on a brush that had no id is applied; the drop used to do nothing while still showing a success toast. (issue [#761](https://github.com/saworbit/hammerforge/issues/761), PR [#766](https://github.com/saworbit/hammerforge/pull/766))
- **18 Sep** A restored brush no longer pushes the brush id counter up; loading a level used to leave it hundreds higher. (issue [#737](https://github.com/saworbit/hammerforge/issues/737), PR [#760](https://github.com/saworbit/hammerforge/pull/760))
- **18 Sep** Four more bake settings travel with the level; a level saved with wire I/O off used to reopen with it on and bake a dispatcher. (issue [#755](https://github.com/saworbit/hammerforge/issues/755), PR [#759](https://github.com/saworbit/hammerforge/pull/759))
- **18 Sep** A level saved with occluders on bakes with them on when reopened; the setting used to revert to off on load. (issue [#710](https://github.com/saworbit/hammerforge/issues/710), PR [#756](https://github.com/saworbit/hammerforge/pull/756))
- **18 Sep** Restoring a level whose saved palette holds junk no longer raises a script error in the Debugger. (issue [#752](https://github.com/saworbit/hammerforge/issues/752), PR [#753](https://github.com/saworbit/hammerforge/pull/753))
- **18 Sep** A mirrored brush (negative scale) no longer bakes inside out, and a mirrored cutter cuts instead of adding to the wall. (issue [#749](https://github.com/saworbit/hammerforge/issues/749), PR [#751](https://github.com/saworbit/hammerforge/pull/751))
- **18 Sep** One subtract brush no longer costs the whole level its per-face materials; any cut used to bake each brush to one material. (issue [#693](https://github.com/saworbit/hammerforge/issues/693), PR [#747](https://github.com/saworbit/hammerforge/pull/747))
- **18 Sep** A `.hfmaterials` file that is not a palette is refused with a reason rather than a script error, and the loaded palette survives. (issue [#739](https://github.com/saworbit/hammerforge/issues/739), PR [#740](https://github.com/saworbit/hammerforge/pull/740))
- **18 Sep** A `.map` keeps which way up it is crossing between editors; a floor exported from here used to open in TrenchBroom as a wall. (issue [#733](https://github.com/saworbit/hammerforge/issues/733), PR [#735](https://github.com/saworbit/hammerforge/pull/735))
- **18 Sep** A `.map` keeps its size crossing between editors, through a new Map units/m row in the File section that defaults to 32. (issue [#713](https://github.com/saworbit/hammerforge/issues/713), PR [#734](https://github.com/saworbit/hammerforge/pull/734))
- **18 Sep** An idle autosave writes nothing; every autosave used to rewrite the file even when nothing had changed. (issue [#716](https://github.com/saworbit/hammerforge/issues/716), PR [#731](https://github.com/saworbit/hammerforge/pull/731))
- **18 Sep** A brush entity's properties can be set; a func_door or func_button drawn in the editor could never be given a speed or wait. (issue [#728](https://github.com/saworbit/hammerforge/issues/728), PR [#730](https://github.com/saworbit/hammerforge/pull/730))
- **18 Sep** A door moves when it is opened, sliding with its collision along its angle and closing itself after its wait. (issue [#687](https://github.com/saworbit/hammerforge/issues/687), PR [#729](https://github.com/saworbit/hammerforge/pull/729))
- **18 Sep** Visgroup and group lists come back in the order they were made; saving and reopening used to sort them alphabetically. (issue [#706](https://github.com/saworbit/hammerforge/issues/706), PR [#727](https://github.com/saworbit/hammerforge/pull/727))
- **18 Sep** The Physics Layer dropdown says what each entry costs, and a level on layer 2 or 3 no longer has its spawn reported as floating. (issue [#695](https://github.com/saworbit/hammerforge/issues/695), PR [#726](https://github.com/saworbit/hammerforge/pull/726))
- **17 Sep** The playtest player can climb the stairs the plugin builds; any step, even five centimetres, used to stop it like a wall. (issue [#711](https://github.com/saworbit/hammerforge/issues/711), PR [#724](https://github.com/saworbit/hammerforge/pull/724))
- **17 Sep** A lightmap unwrap that fails says so; the bake used to report success and LightmapGI baked that surface black. (issue [#700](https://github.com/saworbit/hammerforge/issues/700), PR [#722](https://github.com/saworbit/hammerforge/pull/722))
- **17 Sep** A bake says when a cutter drops the face materials and how many brushes caused it; only a Console line used to. (issue [#694](https://github.com/saworbit/hammerforge/issues/694), PR [#721](https://github.com/saworbit/hammerforge/pull/721))
- **17 Sep** A model set on prop_static appears in the viewport, bake and playtest, and the scatter brush accepts `.glb` and `.gltf` picks. (issues [#690](https://github.com/saworbit/hammerforge/issues/690), [#691](https://github.com/saworbit/hammerforge/issues/691), PR [#720](https://github.com/saworbit/hammerforge/pull/720))
- **17 Sep** An entity definition keeps every key in `entities.json`, so `preview` and `input_methods` are no longer dropped on load. (PR [#720](https://github.com/saworbit/hammerforge/pull/720))
- **17 Sep** A prop's model is packed once; an exported scene used to hold and load the model twice. (PR [#720](https://github.com/saworbit/hammerforge/pull/720))
- **17 Sep** A level in a game scene is a level, not a playtest; a built game used to add a debug FPS player and rebuild the level at load. (issues [#699](https://github.com/saworbit/hammerforge/issues/699), [#689](https://github.com/saworbit/hammerforge/issues/689), PR [#719](https://github.com/saworbit/hammerforge/pull/719))
- **17 Sep** The I/O graph a mapper wires runs: triggers fire OnStartTouch and OnEndTouch, and the playtest Use key presses buttons. (issue [#686](https://github.com/saworbit/hammerforge/issues/686), PR [#718](https://github.com/saworbit/hammerforge/pull/718))
- **17 Sep** An entity class can say which engine method an input means, so logic_timer's Start and Stop work instead of printing a warning. (issue [#714](https://github.com/saworbit/hammerforge/issues/714), PR [#718](https://github.com/saworbit/hammerforge/pull/718))
- **17 Sep** Save As writes the file; saving an unchanged level to a new name used to report success and write nothing. (issue [#688](https://github.com/saworbit/hammerforge/issues/688), PR [#717](https://github.com/saworbit/hammerforge/pull/717))
- **17 Sep** A turn keeps a face's texture the right way round; a wall yawed a quarter turn used to come back mirrored. (issue [#684](https://github.com/saworbit/hammerforge/issues/684), PR [#685](https://github.com/saworbit/hammerforge/pull/685))
- **17 Sep** Texture Lock carries a turning brush's texture the way it carries a moving one's; a box's top and bottom used to turn the wrong way. (issue [#684](https://github.com/saworbit/hammerforge/issues/684), PR [#685](https://github.com/saworbit/hammerforge/pull/685))
- **17 Sep** A texture runs across a wall built from several brushes instead of restarting at every brush edge, so Treat as one finally works. (issues [#652](https://github.com/saworbit/hammerforge/issues/652), [#653](https://github.com/saworbit/hammerforge/issues/653), PR [#683](https://github.com/saworbit/hammerforge/pull/683))
- **17 Sep** Texture Lock keeps the texture on a moving brush when ticked and on the world grid when unticked; the checkbox used to work backwards. (issue [#653](https://github.com/saworbit/hammerforge/issues/653), PR [#683](https://github.com/saworbit/hammerforge/pull/683))
- **17 Sep** Levels saved before the switch to level-space texturing keep any texture offset set by hand, and rotated brushes keep their old look. (issue [#652](https://github.com/saworbit/hammerforge/issues/652), PR [#683](https://github.com/saworbit/hammerforge/pull/683))
- **17 Sep** Tie to Entity takes a name so a brush entity can be targeted, and a two-leaf door exports and plays as one door instead of two. (issue [#668](https://github.com/saworbit/hammerforge/issues/668), PR [#682](https://github.com/saworbit/hammerforge/pull/682))
- **17 Sep** The prefab search hides prefabs that do not match instead of dimming them, and a `.hfprefab` that will not parse shows disabled. (issue [#667](https://github.com/saworbit/hammerforge/issues/667), PR [#681](https://github.com/saworbit/hammerforge/pull/681))
- **17 Sep** The Polygon tool height, `door_basic` speed and the bevel, inset and displacement paint sliders fit the one-unit-per-metre scale. (issue [#658](https://github.com/saworbit/hammerforge/issues/658), PR [#680](https://github.com/saworbit/hammerforge/pull/680))
- **17 Sep** Bake chunking works on the default face-material bake, where Chunk Size used to do nothing; `bake_chunk_size` now defaults to 0, one mesh. (issue [#656](https://github.com/saworbit/hammerforge/issues/656), PR [#679](https://github.com/saworbit/hammerforge/pull/679))
- **17 Sep** Justify moves a hand-made UV layout instead of throwing it away; it used to lose the alignment and still miss the button's result. (issue [#654](https://github.com/saworbit/hammerforge/issues/654), PR [#677](https://github.com/saworbit/hammerforge/pull/677))
- **17 Sep** Validate checks convexity, the spawn and missing prefab files; Merge refuses brushes that do not touch, and the default spawn stands on the floor. (issues [#657](https://github.com/saworbit/hammerforge/issues/657), [#666](https://github.com/saworbit/hammerforge/issues/666), [#669](https://github.com/saworbit/hammerforge/issues/669), PR [#676](https://github.com/saworbit/hammerforge/pull/676))
- **17 Sep** An undo puts brushes back in their old order instead of at the end, so saved files stop churning and CSG cuts stay as set up. (issue [#660](https://github.com/saworbit/hammerforge/issues/660), PR [#675](https://github.com/saworbit/hammerforge/pull/675))
- **17 Sep** A `.map` keeps its texture names and entity keys through import and export; a door used to lose `speed` and every face became `__default`. (issues [#662](https://github.com/saworbit/hammerforge/issues/662), [#663](https://github.com/saworbit/hammerforge/issues/663), PR [#674](https://github.com/saworbit/hammerforge/pull/674))
- **17 Sep** Each level autosaves to its own file; every level in a project used to share one autosave file and overwrite each other's. (issue [#655](https://github.com/saworbit/hammerforge/issues/655), PR [#673](https://github.com/saworbit/hammerforge/pull/673))
- **17 Sep** Ctrl+S keeps visgroups, groups, arrays, hollows, generators, prefab instances, paint layers and surface paint, not only the brushes. (issues [#664](https://github.com/saworbit/hammerforge/issues/664), [#665](https://github.com/saworbit/hammerforge/issues/665), PR [#672](https://github.com/saworbit/hammerforge/pull/672))
- **17 Sep** Each baked occluder covers one flat surface rather than every wall on its plane; it used to span the whole level and never cull. (issue [#614](https://github.com/saworbit/hammerforge/issues/614), PR [#640](https://github.com/saworbit/hammerforge/pull/640))
- **17 Sep** Convert to Heightmap no longer throws an engine error on its first read, and a paint layer holding paint refuses a chunk size change. (issue [#625](https://github.com/saworbit/hammerforge/issues/625), PR [#638](https://github.com/saworbit/hammerforge/pull/638))
- **17 Sep** A prefab keeps its materials when placed in another level; it used to re-texture with whatever sat in the same palette slots. (issue [#621](https://github.com/saworbit/hammerforge/issues/621), PR [#637](https://github.com/saworbit/hammerforge/pull/637))
- **17 Sep** The shortcut dialog opens from a ? button on the dock, and custom tools go in `res://hammerforge_tools/` so an upgrade no longer deletes them. (issues [#606](https://github.com/saworbit/hammerforge/issues/606), [#612](https://github.com/saworbit/hammerforge/issues/612), PR [#636](https://github.com/saworbit/hammerforge/pull/636))
- **17 Sep** Generate LODs produces LOD levels, and Use atlas reports what it packed or why it skipped; both used to do nothing without a word. (issues [#611](https://github.com/saworbit/hammerforge/issues/611), [#623](https://github.com/saworbit/hammerforge/issues/623), PR [#635](https://github.com/saworbit/hammerforge/pull/635))
- **17 Sep** The door previews as a box instead of a light bulb, and entity classes offer their outputs and inputs in the quick-wire dropdowns. (issue [#613](https://github.com/saworbit/hammerforge/issues/613), PR [#634](https://github.com/saworbit/hammerforge/pull/634))
- **17 Sep** The Objects tab lists an entity's connections once, and Remove Output sits on the wiring panel beside the list it acts on. (issue [#616](https://github.com/saworbit/hammerforge/issues/616), PR [#633](https://github.com/saworbit/hammerforge/pull/633))
- **17 Sep** Test Level builds each entity as the node or scene its definition names; a placed light used to export as a bare node, so moving it changed nothing. (issues [#598](https://github.com/saworbit/hammerforge/issues/598), [#599](https://github.com/saworbit/hammerforge/issues/599), PR [#632](https://github.com/saworbit/hammerforge/pull/632))
- **16 Sep** A broken I/O wire shows as a red mast in the viewport and is named by Validate, and an entity wired to itself counts as firing itself. (issues [#602](https://github.com/saworbit/hammerforge/issues/602), [#603](https://github.com/saworbit/hammerforge/issues/603), [#620](https://github.com/saworbit/hammerforge/issues/620), PR [#631](https://github.com/saworbit/hammerforge/pull/631))
- **16 Sep** A cylinder, cone or sphere lands inside the dragged rectangle, and a sphere's height drag sets its size; a round brush used to overshoot. (issues [#604](https://github.com/saworbit/hammerforge/issues/604), [#605](https://github.com/saworbit/hammerforge/issues/605), PR [#630](https://github.com/saworbit/hammerforge/pull/630))
- **16 Sep** Autosaving one level no longer deletes another level's backups, and saves within the same second no longer overwrite each other. (issue [#618](https://github.com/saworbit/hammerforge/issues/618), PR [#629](https://github.com/saworbit/hammerforge/pull/629))
- **16 Sep** Settings hold to their declared range; an autosave interval above 60 silently stopped autosaving, and the Console cut chunk size to 256. (issues [#622](https://github.com/saworbit/hammerforge/issues/622), [#607](https://github.com/saworbit/hammerforge/issues/607), PR [#628](https://github.com/saworbit/hammerforge/pull/628))
- **16 Sep** The `.hflevel` save keeps value types it used to turn into unreadable strings, and warns about anything it cannot write. (issues [#619](https://github.com/saworbit/hammerforge/issues/619), [#617](https://github.com/saworbit/hammerforge/issues/617), PR [#627](https://github.com/saworbit/hammerforge/pull/627))
- **16 Sep** Undoing a brush resize no longer renames every brush in the level, which silently unwired every I/O connection. (PR [#597](https://github.com/saworbit/hammerforge/pull/597))
- **16 Sep** Clicking a brush in the 3D viewport no longer throws you onto the HammerForge main screen. (issue [#592](https://github.com/saworbit/hammerforge/issues/592), PR [#594](https://github.com/saworbit/hammerforge/pull/594))
- **16 Sep** Auto connector mode's stairs-vs-ramp threshold is a setting saved with the level, default 32; Auto used to pick Stairs everywhere. (issue [#570](https://github.com/saworbit/hammerforge/issues/570), PR [#591](https://github.com/saworbit/hammerforge/pull/591))
- **16 Sep** A tool that cannot start says why and stays off; Decal and Measure used to go active with no level in the scene and do nothing. (issue [#552](https://github.com/saworbit/hammerforge/issues/552), PR [#589](https://github.com/saworbit/hammerforge/pull/589))
- **16 Sep** A custom tool's declared settings appear as controls in a Tool Settings section on the Build tab. (issue [#554](https://github.com/saworbit/hammerforge/issues/554), PR [#589](https://github.com/saworbit/hammerforge/pull/589))
- **16 Sep** Material browser favourites survive a theme change, project reload or editor restart. (issue [#545](https://github.com/saworbit/hammerforge/issues/545), PR [#588](https://github.com/saworbit/hammerforge/pull/588))
- **16 Sep** Starring one unsaved material no longer stars every unsaved material; the dock asks you to save it to disk first. (issue [#544](https://github.com/saworbit/hammerforge/issues/544), PR [#588](https://github.com/saworbit/hammerforge/pull/588))
- **16 Sep** A radial array about an axis that does not exist is refused instead of being built about Z and reported as a success. (issue [#541](https://github.com/saworbit/hammerforge/issues/541), PR [#587](https://github.com/saworbit/hammerforge/pull/587))
- **16 Sep** A grid array count below one is refused from the dock too, instead of being built as an array nobody described. (issue [#542](https://github.com/saworbit/hammerforge/issues/542), PR [#587](https://github.com/saworbit/hammerforge/pull/587))
- **16 Sep** A clip on an axis that does not exist is refused; it used to cut on Z or X and report that axis. (issue [#567](https://github.com/saworbit/hammerforge/issues/567), PR [#587](https://github.com/saworbit/hammerforge/pull/587))
- **16 Sep** Validate + Fix reports how many issues it fixed and lists what remains, instead of reprinting the ones it had just repaired. (issue [#569](https://github.com/saworbit/hammerforge/issues/569), PR [#583](https://github.com/saworbit/hammerforge/pull/583))
- **16 Sep** The Status board's recommended chunk size is one the editor can accept; the dock capped it at 256 while the log claimed more. (issue [#549](https://github.com/saworbit/hammerforge/issues/549), PR [#583](https://github.com/saworbit/hammerforge/pull/583))
- **16 Sep** The Log tab footer says how many lines the buffer really holds. (issue [#543](https://github.com/saworbit/hammerforge/issues/543), PR [#583](https://github.com/saworbit/hammerforge/pull/583))
- **16 Sep** Cycling a prefab variant leaves the instance where it was; each press used to walk an asymmetric prefab further away. (issue [#565](https://github.com/saworbit/hammerforge/issues/565), PR [#582](https://github.com/saworbit/hammerforge/pull/582))
- **16 Sep** A chord built on a tool shortcut key is no longer that tool; Ctrl+M or Shift+M used to switch to Measure. (issue [#574](https://github.com/saworbit/hammerforge/issues/574), PR [#580](https://github.com/saworbit/hammerforge/pull/580))
- **16 Sep** Save Prefab and Cycle Variant can be rebound and show in the shortcut dialog; a rebind onto their chord used to lose silently. (issue [#575](https://github.com/saworbit/hammerforge/issues/575), PR [#580](https://github.com/saworbit/hammerforge/pull/580))
- **16 Sep** The context toolbar tooltips follow rebound shortcuts; rebinding Hollow left the toolbar saying Ctrl+H. (issue [#560](https://github.com/saworbit/hammerforge/issues/560), PR [#580](https://github.com/saworbit/hammerforge/pull/580))
- **16 Sep** Load Material Library and the two terrain slot commands can be undone; Ctrl+Z skipped a library load that repainted every face. (issue [#573](https://github.com/saworbit/hammerforge/issues/573), PR [#579](https://github.com/saworbit/hammerforge/pull/579))
- **16 Sep** Inference cleanup leaves a one-cell stroke alone; a single click used to paint nothing. (issue [#546](https://github.com/saworbit/hammerforge/issues/546), PR [#578](https://github.com/saworbit/hammerforge/pull/578))
- **16 Sep** A one-cell dab is not read as a closed room; a loop needs three cells. (issue [#547](https://github.com/saworbit/hammerforge/issues/547), PR [#578](https://github.com/saworbit/hammerforge/pull/578))
- **16 Sep** Reconciling one floor paint layer no longer deletes other layers' geometry in the same chunk; a bake could ship missing a floor. (issue [#561](https://github.com/saworbit/hammerforge/issues/561), PR [#577](https://github.com/saworbit/hammerforge/pull/577))
- **16 Sep** Paint layer ids are checked as valid node names; a colon in a layer id from another tool duplicated floor and wall geometry. (issue [#548](https://github.com/saworbit/hammerforge/issues/548), PR [#577](https://github.com/saworbit/hammerforge/pull/577))
- **16 Sep** Save Preset no longer suggests a name already in use; deleting a preset could leave two buttons reading Preset 3. (issue [#513](https://github.com/saworbit/hammerforge/issues/513), PR [#537](https://github.com/saworbit/hammerforge/pull/537))
- **16 Sep** A `.hflevel` from a newer build is refused before anything loads, rather than half-read over the open level. (issue [#499](https://github.com/saworbit/hammerforge/issues/499), PR [#536](https://github.com/saworbit/hammerforge/pull/536))
- **16 Sep** Editing a brush entity's metadata marks the bake stale; Bake Changed used to report nothing to do. (issue [#510](https://github.com/saworbit/hammerforge/issues/510), PR [#534](https://github.com/saworbit/hammerforge/pull/534))
- **16 Sep** A cylinder exports to `.map` with the sides it is drawn with; it used to export as a hexagon with textures on the wrong walls. (issue [#495](https://github.com/saworbit/hammerforge/issues/495), PR [#533](https://github.com/saworbit/hammerforge/pull/533))
- **16 Sep** An entity input reaches its handler whatever arguments the handler takes; a mismatch used to error and skip every fallback. (issue [#497](https://github.com/saworbit/hammerforge/issues/497), PR [#532](https://github.com/saworbit/hammerforge/pull/532))
- **16 Sep** The UV editor panel shows the face it is given; it was blank on every brush and a drag broke the face's UVs. (issue [#506](https://github.com/saworbit/hammerforge/issues/506), PR [#531](https://github.com/saworbit/hammerforge/pull/531))
- **16 Sep** Convert to Heightmap keeps its grid within 2048 a side, and its remove-sources setting removes the brushes it converted. (issues [#511](https://github.com/saworbit/hammerforge/issues/511), [#512](https://github.com/saworbit/hammerforge/issues/512), PR [#530](https://github.com/saworbit/hammerforge/pull/530))
- **16 Sep** A dimension typed during a draw drag shows on the brush and keeps the drag's direction; it used to jump to the opposite quadrant. (issues [#516](https://github.com/saworbit/hammerforge/issues/516), [#517](https://github.com/saworbit/hammerforge/issues/517), PR [#529](https://github.com/saworbit/hammerforge/pull/529))
- **16 Sep** Custom tool loading no longer runs scripts it is going to refuse, and an unknown tool id leaves the current tool on. (issues [#507](https://github.com/saworbit/hammerforge/issues/507), [#508](https://github.com/saworbit/hammerforge/issues/508), [#509](https://github.com/saworbit/hammerforge/issues/509), PR [#528](https://github.com/saworbit/hammerforge/pull/528))
- **16 Sep** Generator settings are held to their minimum and their enum options; a staircase could build zero-thickness treads. (issues [#518](https://github.com/saworbit/hammerforge/issues/518), [#519](https://github.com/saworbit/hammerforge/issues/519), PR [#527](https://github.com/saworbit/hammerforge/pull/527))
- **16 Sep** A brush entity answers to its authored name; outputs aimed at a door or button never resolved. (issue [#493](https://github.com/saworbit/hammerforge/issues/493), PR [#526](https://github.com/saworbit/hammerforge/pull/526))
- **16 Sep** The default bake generates the LODs and lightmap UV2 the Bake Options ask for; it used to drop them. (issue [#494](https://github.com/saworbit/hammerforge/issues/494), PR [#525](https://github.com/saworbit/hammerforge/pull/525))
- **16 Sep** A new, untouched level passes its own validator; the empty-palette warning fires only when a face uses a palette slot. (issue [#514](https://github.com/saworbit/hammerforge/issues/514), PR [#525](https://github.com/saworbit/hammerforge/pull/525))
- **16 Sep** Exported `.map` faces write rotation in degrees and scale as `.map` readers expect; a zero scale no longer divides by zero. (issues [#503](https://github.com/saworbit/hammerforge/issues/503), [#504](https://github.com/saworbit/hammerforge/issues/504), [#505](https://github.com/saworbit/hammerforge/issues/505), PR [#524](https://github.com/saworbit/hammerforge/pull/524))

#### Security

- **17 Sep** A prefab name can no longer write outside the prefab folder; `../escape` used to save beside `project.godot`. A failed save now says so. (issue [#667](https://github.com/saworbit/hammerforge/issues/667), PR [#681](https://github.com/saworbit/hammerforge/pull/681))

#### Behind the scenes

- **19 Sep** `restore_state()` refuses an undo scope instead of reading it as an empty level that frees every brush outside the scope. (issue [#768](https://github.com/saworbit/hammerforge/issues/768), PR [#769](https://github.com/saworbit/hammerforge/pull/769))
- **18 Sep** `tools/wait_for_ci.py` takes a commit as well as a pull request, so a squash merge on main can be checked. (issue [#763](https://github.com/saworbit/hammerforge/issues/763), PR [#764](https://github.com/saworbit/hammerforge/pull/764))
- **18 Sep** The `docs-truth` vibe scenario no longer flags a `.map` measurement in Quake units as HammerForge's own scale. (issue [#754](https://github.com/saworbit/hammerforge/issues/754), PR [#758](https://github.com/saworbit/hammerforge/pull/758))
- **18 Sep** Shipping a Level now says baked surfaces keep Godot's default friction and bounce, and where a game should tune them. (issue [#744](https://github.com/saworbit/hammerforge/issues/744), PR [#748](https://github.com/saworbit/hammerforge/pull/748))
- **18 Sep** A vibe scenario that hits a script error is graded as a failure instead of being reported clean. (issue [#739](https://github.com/saworbit/hammerforge/issues/739), PR [#740](https://github.com/saworbit/hammerforge/pull/740))
- **18 Sep** CI stops going red on a failed download; the fetch retries, checks the zip is whole and logs the server's answer. (PR [#732](https://github.com/saworbit/hammerforge/pull/732))
- **17 Sep** Two unreachable pieces of code are removed: a duplicate `stretch` Justify mode and an Apply Material context-menu entry never added. (issues [#654](https://github.com/saworbit/hammerforge/issues/654), [#670](https://github.com/saworbit/hammerforge/issues/670), PR [#677](https://github.com/saworbit/hammerforge/pull/677))
- **17 Sep** `tools/check_dead_declarations.py` finds GDScript declarations nothing calls, telling a call site from a mention; CI runs it. (issue [#647](https://github.com/saworbit/hammerforge/issues/647), PR [#651](https://github.com/saworbit/hammerforge/pull/651))
- **17 Sep** Five private declarations nothing called are removed, found by the new dead-declaration check on its first run. (issue [#647](https://github.com/saworbit/hammerforge/issues/647), PR [#651](https://github.com/saworbit/hammerforge/pull/651))
- **17 Sep** The test suite runs in four CI shards, cutting a CI run from 6m33s to 2m21s with the same coverage. (issue [#648](https://github.com/saworbit/hammerforge/issues/648), PR [#649](https://github.com/saworbit/hammerforge/pull/649))
- **16 Sep** Two release gate checks are corrected by running the gate: Create Starter Level is two undo steps, and a clean bake logs nothing. (issue [#593](https://github.com/saworbit/hammerforge/issues/593), PR [#596](https://github.com/saworbit/hammerforge/pull/596))
- **16 Sep** The editor smoke checklist is a short release gate plus a long reference, and a release fails unless the gate records its version. (issue [#593](https://github.com/saworbit/hammerforge/issues/593), PR [#595](https://github.com/saworbit/hammerforge/pull/595))
- **16 Sep** Nineteen public functions with no caller are removed. (issue [#572](https://github.com/saworbit/hammerforge/issues/572), PR [#591](https://github.com/saworbit/hammerforge/pull/591))
- **16 Sep** Three dead dock functions are removed, including a `set_status_grid()` that did nothing. (issue [#555](https://github.com/saworbit/hammerforge/issues/555), PR [#591](https://github.com/saworbit/hammerforge/pull/591))
- **16 Sep** The unread `autosave_interval` and `last_tool_id` preferences are removed; `hflevel_autosave_minutes` is the autosave interval that works. (issue [#568](https://github.com/saworbit/hammerforge/issues/568), PR [#591](https://github.com/saworbit/hammerforge/pull/591))
- **16 Sep** The floor paint tool's unconnected `material_picked` signal is removed; the Ctrl+Click eyedropper still works. (issue [#553](https://github.com/saworbit/hammerforge/issues/553), PR [#590](https://github.com/saworbit/hammerforge/pull/590))
- **16 Sep** The prefab folder is one shared constant, and a setter that could change only one of its three copies is removed. (issue [#556](https://github.com/saworbit/hammerforge/issues/556), PR [#590](https://github.com/saworbit/hammerforge/pull/590))
- **16 Sep** The visgroup colour, which nothing ever read, is dropped from saves and undo snapshots; older files still load. (issue [#551](https://github.com/saworbit/hammerforge/issues/551), PR [#586](https://github.com/saworbit/hammerforge/pull/586))
- **16 Sep** The unused `HFGesture` class and its guide section are removed; it carried a stale copy of a fixed keypad Enter bug. (issue [#550](https://github.com/saworbit/hammerforge/issues/550), PR [#585](https://github.com/saworbit/hammerforge/pull/585))
- **16 Sep** The unused `HFFoliagePopulator` is removed, and the guide documents `HFScatterBrush`, which the Paint tab actually uses. (issue [#562](https://github.com/saworbit/hammerforge/issues/562), PR [#585](https://github.com/saworbit/hammerforge/pull/585))
- **16 Sep** The state system's uncalled transaction API is removed. (issue [#571](https://github.com/saworbit/hammerforge/issues/571), PR [#585](https://github.com/saworbit/hammerforge/pull/585))
- **16 Sep** Five fields that were assigned and never read are removed. (issue [#564](https://github.com/saworbit/hammerforge/issues/564), PR [#584](https://github.com/saworbit/hammerforge/pull/584))
- **16 Sep** The unreachable per-instance prefab override mechanism is removed; older saves that carry overrides still load. (issue [#566](https://github.com/saworbit/hammerforge/issues/566), PR [#582](https://github.com/saworbit/hammerforge/pull/582))
- **16 Sep** CI format-checks and lints the `tools/` scripts too; sixty-six files had sat outside both checks and drifted. (issue [#500](https://github.com/saworbit/hammerforge/issues/500), PR [#539](https://github.com/saworbit/hammerforge/pull/539))
- **16 Sep** The README At a Glance test count is updated by `tools/update_test_counts.py`; it had been stuck at 2,860. (issue [#502](https://github.com/saworbit/hammerforge/issues/502), PR [#539](https://github.com/saworbit/hammerforge/pull/539))
- **16 Sep** Five signals that were declared and never emitted are removed, with their dead handlers. (issue [#521](https://github.com/saworbit/hammerforge/issues/521), PR [#538](https://github.com/saworbit/hammerforge/pull/538))
- **16 Sep** The unread `angle_snap_degrees` floor paint inference setting is removed. (issue [#520](https://github.com/saworbit/hammerforge/issues/520), PR [#538](https://github.com/saworbit/hammerforge/pull/538))
- **16 Sep** Four floor paint inference settings become on/off switches named for what they do; the engine is still unwired. (issue [#520](https://github.com/saworbit/hammerforge/issues/520), PR [#538](https://github.com/saworbit/hammerforge/pull/538))
- **16 Sep** A whole-tree test checks that every signal the addon declares is emitted. (issue [#521](https://github.com/saworbit/hammerforge/issues/521), PR [#538](https://github.com/saworbit/hammerforge/pull/538))
- **16 Sep** A brush shape test no longer leaks a CSG cylinder. (issue [#496](https://github.com/saworbit/hammerforge/issues/496), PR [#533](https://github.com/saworbit/hammerforge/pull/533))

### Week of 7 Sep 2026

#### Added

- **10 Sep** Create Starter can run without the dock, through `HFLevelFactory.create_starter()` for scripts, tools and editor bridges. (issue [#278](https://github.com/saworbit/hammerforge/issues/278), PR [#279](https://github.com/saworbit/hammerforge/pull/279))
- **10 Sep** Floor Paint lays out a whole first room: footprint, wall height, mirror copies, room stamps and confirmed ramp or stair connectors. (PR [#273](https://github.com/saworbit/hammerforge/pull/273))
- **9 Sep** Re-hollow counts the walls you moved, resized or repainted, names Detach, and needs a second press before rebuilding over them. (PR [#249](https://github.com/saworbit/hammerforge/pull/249))
- **9 Sep** A hollowed brush can be shelled again at a new thickness: select a wall to get Re-hollow and Detach in the Hollow row. (PR [#240](https://github.com/saworbit/hammerforge/pull/240))
- **9 Sep** Update on an array warns how many hand-moved copies it would put back, names Detach, and needs a second press. (PR [#236](https://github.com/saworbit/hammerforge/pull/236))
- **9 Sep** Selecting any piece of an array opens it for editing: change its layout and numbers, then Update Array or Detach it. (PR [#234](https://github.com/saworbit/hammerforge/pull/234))
- **9 Sep** The array section draws a ghost of the copies, says how many you will get, and refuses arrays over 256 brushes. (PR [#216](https://github.com/saworbit/hammerforge/pull/216))
- **9 Sep** A structure built on a turned selection faces the same way; an arch on a 45-degree wall used to stand square. (PR [#215](https://github.com/saworbit/hammerforge/pull/215))
- **8 Sep** The Structure section draws a wireframe ghost of what Create or Update would build, following every setting as you change it. (PR [#212](https://github.com/saworbit/hammerforge/pull/212))
- **8 Sep** Stairs, Spiral stairs and Dome join the arch in a structure library, built from one Structure section with a type dropdown. (PR [#189](https://github.com/saworbit/hammerforge/pull/189))
- **8 Sep** A structure you have moved rebuilds where it now is; widening a dragged arch used to put it back at its origin. (PR [#189](https://github.com/saworbit/hammerforge/pull/189))
- **8 Sep** The Structure section says how many pieces were edited by hand and would be rebuilt over by Update, with Detach beside it. (PR [#189](https://github.com/saworbit/hammerforge/pull/189))
- **8 Sep** A structure you have turned rebuilds turned, instead of squaring up to the world axes and calling every piece hand-edited. (PR [#188](https://github.com/saworbit/hammerforge/pull/188))
- **8 Sep** Live generators: select an arch piece to load its settings, then Update it in place keeping materials, or Detach it. (PR [#188](https://github.com/saworbit/hammerforge/pull/188))
- **8 Sep** Hollow works on any convex brush at any rotation, a parametric Arch builds one brush per stone, and radial arrays can rise into a helix. (PR [#187](https://github.com/saworbit/hammerforge/pull/187))
- **8 Sep** Clip and Carve cut along any plane on any convex brush at any rotation, previews show the real cut, and Clip to Face Plane is new. (PR [#186](https://github.com/saworbit/hammerforge/pull/186))
- **8 Sep** Brushes can be rotated (R), flipped (Shift+M) and reset (Alt+R), and Duplicate Array gains Radial and Grid layouts. (PR [#185](https://github.com/saworbit/hammerforge/pull/185))

#### Changed

- **13 Sep** Surface painting is about three times faster, 17 ms a sample instead of 52 ms. (issue [#465](https://github.com/saworbit/hammerforge/issues/465), PR [#487](https://github.com/saworbit/hammerforge/pull/487))
- **13 Sep** Live auto-connectors cost the stroke instead of the whole level; a stroke on a large painted level took 39 ms while dragging. (issue [#441](https://github.com/saworbit/hammerforge/issues/441), PR [#462](https://github.com/saworbit/hammerforge/pull/462))
- **12 Sep** A vertex move that bends a face now splits it into triangles instead of being refused, so a single box corner can be dragged. (PR [#396](https://github.com/saworbit/hammerforge/pull/396))
- **11 Sep** A face takes at most 8 surface paint layers; more added preview, save and load time with no visible difference. (issue [#351](https://github.com/saworbit/hammerforge/issues/351), PR [#362](https://github.com/saworbit/hammerforge/pull/362))
- **11 Sep** Non-box shapes store one face per flat surface, not per triangle; a cylinder has 66 faces instead of 768 and saves faster. (issue [#322](https://github.com/saworbit/hammerforge/issues/322), PR [#328](https://github.com/saworbit/hammerforge/pull/328))
- **10 Sep** Check Issues runs about four times faster on large levels; 1,000 brushes went from 1.8 s to 0.46 s. (PR [#274](https://github.com/saworbit/hammerforge/pull/274))
- **10 Sep** Precision snap skips brushes out of the pointer's reach, so its cost no longer grows with the size of the level. (PR [#268](https://github.com/saworbit/hammerforge/pull/268))
- **10 Sep** Check Issues' subtraction checks compare only brushes that overlap; on 1,000 brushes they went from 118 ms to 11 ms. (PR [#267](https://github.com/saworbit/hammerforge/pull/267))
- **10 Sep** The Performance section only measures the level while it is open and on screen, so an idle editor stops paying for it. (PR [#266](https://github.com/saworbit/hammerforge/pull/266))
- **10 Sep** The entity wiring overlay redraws only when the wiring changes, instead of six times a second whether anything moved or not. (PR [#265](https://github.com/saworbit/hammerforge/pull/265))
- **9 Sep** The array edit warning also counts copies resized, reshaped, retextured or given a paint layer, not only moved ones. (PR [#239](https://github.com/saworbit/hammerforge/pull/239))
- **8 Sep** The dock's Arch section is now the Structure section with a type dropdown; Ctrl+Shift+A builds whichever type it shows. (PR [#189](https://github.com/saworbit/hammerforge/pull/189))
- **8 Sep** Hollow and Carve refuse brushes with more than 128 planes and say how many; hollowing a sphere took a minute and made 2,051 brushes. (PR [#187](https://github.com/saworbit/hammerforge/pull/187))

#### Fixed

- **13 Sep** Entity colours, vectors and flags are written into a `.map` in `.map` notation; a colour used to reach the file unusable. (issue [#479](https://github.com/saworbit/hammerforge/issues/479), PR [#492](https://github.com/saworbit/hammerforge/pull/492))
- **13 Sep** Per-face materials reach the baked mesh by default; a textured level used to bake with one material and no warning. (issue [#466](https://github.com/saworbit/hammerforge/issues/466), PR [#491](https://github.com/saworbit/hammerforge/pull/491))
- **13 Sep** Set Cordon from Selection leaves a cordon that contains the selection; a room past 9999 used to bake an empty level. (issue [#467](https://github.com/saworbit/hammerforge/issues/467), PR [#490](https://github.com/saworbit/hammerforge/pull/490))
- **13 Sep** Every face of a new brush can show a texture; four of a box's six faces used to sample a single row of texels. (issue [#463](https://github.com/saworbit/hammerforge/issues/463), PR [#489](https://github.com/saworbit/hammerforge/pull/489))
- **13 Sep** A cylinder cap can show a texture too; both caps used to sample a single line of it. (issue [#463](https://github.com/saworbit/hammerforge/issues/463), PR [#489](https://github.com/saworbit/hammerforge/pull/489))
- **13 Sep** A cylinder or cone is built with the sides it was given; the preview always used 64 and disagreed with the bake. (issue [#482](https://github.com/saworbit/hammerforge/issues/482), PR [#489](https://github.com/saworbit/hammerforge/pull/489))
- **13 Sep** The playtest starts the player standing on the spawn point; it used to start 0.7 units inside the floor. (issue [#468](https://github.com/saworbit/hammerforge/issues/468), PR [#488](https://github.com/saworbit/hammerforge/pull/488))
- **13 Sep** Crouch in the playtest shrinks the player and lowers the camera; Ctrl used to only slow you down. (issue [#469](https://github.com/saworbit/hammerforge/issues/469), PR [#488](https://github.com/saworbit/hammerforge/pull/488))
- **13 Sep** A surface paint stroke lands under the cursor; on any face larger than one unit it used to land in a corner. (issue [#464](https://github.com/saworbit/hammerforge/issues/464), PR [#487](https://github.com/saworbit/hammerforge/pull/487))
- **13 Sep** Import Settings checks each value it reads; a quoted number in a `.hfsettings` file used to turn snapping off silently. (issue [#478](https://github.com/saworbit/hammerforge/issues/478), PR [#486](https://github.com/saworbit/hammerforge/pull/486))
- **13 Sep** Import Settings writes the connector mode to the level; the dropdown could say Auto while the bake ran Ramp. (issue [#477](https://github.com/saworbit/hammerforge/issues/477), PR [#486](https://github.com/saworbit/hammerforge/pull/486))
- **13 Sep** `bake_collision_mode` and `bake_connector_mode` only take modes that exist; a bad value from a file baked as another mode. (issue [#480](https://github.com/saworbit/hammerforge/issues/480), PR [#486](https://github.com/saworbit/hammerforge/pull/486))
- **13 Sep** A bake chunk size of 0 turns chunking off; it used to give one-unit chunks, the slowest bake available. (issue [#481](https://github.com/saworbit/hammerforge/issues/481), PR [#486](https://github.com/saworbit/hammerforge/pull/486))
- **13 Sep** Every dock command that changes the level registers an undo step; Ctrl+Z after Delete Visgroup used to undo something else. (issues [#470](https://github.com/saworbit/hammerforge/issues/470), [#471](https://github.com/saworbit/hammerforge/issues/471), [#472](https://github.com/saworbit/hammerforge/issues/472), [#473](https://github.com/saworbit/hammerforge/issues/473), [#474](https://github.com/saworbit/hammerforge/issues/474), [#475](https://github.com/saworbit/hammerforge/issues/475), PR [#485](https://github.com/saworbit/hammerforge/pull/485))
- **13 Sep** A redo of a selection or entity command no longer reaches for a node the undo freed. (PR [#485](https://github.com/saworbit/hammerforge/pull/485))
- **13 Sep** Wiring panel connections and presets are undoable; undoing a preset used to mean deleting a dozen connections by hand. (issue [#473](https://github.com/saworbit/hammerforge/issues/473), PR [#485](https://github.com/saworbit/hammerforge/pull/485))
- **13 Sep** Add Sel leaves the visgroup row selected; the next Add Sel, Rem Sel or Delete used to do nothing. (issue [#476](https://github.com/saworbit/hammerforge/issues/476), PR [#485](https://github.com/saworbit/hammerforge/pull/485))
- **13 Sep** The HUD, coach marks and tooltips show rebound shortcuts, and the rebind list no longer shows Extrude Up and Down twice. (issues [#439](https://github.com/saworbit/hammerforge/issues/439), [#440](https://github.com/saworbit/hammerforge/issues/440), PR [#461](https://github.com/saworbit/hammerforge/pull/461))
- **13 Sep** The operation timeline's Replay button can be clicked, and its glyphs match the operation; Clear Brushes showed as a creation. (issues [#437](https://github.com/saworbit/hammerforge/issues/437), [#438](https://github.com/saworbit/hammerforge/issues/438), PR [#460](https://github.com/saworbit/hammerforge/pull/460))
- **13 Sep** The G G, B B and R R popups use the ranges of the controls they set; R R and Enter used to max out the paint radius. (issues [#447](https://github.com/saworbit/hammerforge/issues/447), [#448](https://github.com/saworbit/hammerforge/issues/448), PR [#459](https://github.com/saworbit/hammerforge/pull/459))
- **13 Sep** A tool setting is held to its own limits wherever the value comes from; a negative path width built an inside-out corridor. (issue [#450](https://github.com/saworbit/hammerforge/issues/450), PR [#458](https://github.com/saworbit/hammerforge/pull/458))
- **13 Sep** The region memory budget counts only what it freed; on an unsaved level Memory Budget did nothing, and now says to save. (issue [#446](https://github.com/saworbit/hammerforge/issues/446), PR [#457](https://github.com/saworbit/hammerforge/pull/457))
- **13 Sep** The Walls, Floors and Ceilings filters cover sloped faces, skip hidden brushes, and say when nothing matched. (issues [#434](https://github.com/saworbit/hammerforge/issues/434), [#435](https://github.com/saworbit/hammerforge/issues/435), [#436](https://github.com/saworbit/hammerforge/issues/436), PR [#456](https://github.com/saworbit/hammerforge/pull/456))
- **13 Sep** Loading an example level asks first and is one undo step; one click used to wipe the level with no undo. (issues [#443](https://github.com/saworbit/hammerforge/issues/443), [#444](https://github.com/saworbit/hammerforge/issues/444), PR [#455](https://github.com/saworbit/hammerforge/pull/455))
- **13 Sep** Deleting a paint layer keeps the chosen one active, layer ids stay unique, and every layer follows a moved level root. (issues [#432](https://github.com/saworbit/hammerforge/issues/432), [#433](https://github.com/saworbit/hammerforge/issues/433), [#442](https://github.com/saworbit/hammerforge/issues/442), PR [#454](https://github.com/saworbit/hammerforge/pull/454))
- **13 Sep** A committed scatter is saved with the scene and undoable, Align to Normal is upright, and strokes past 50,000 are refused. (issues [#429](https://github.com/saworbit/hammerforge/issues/429), [#430](https://github.com/saworbit/hammerforge/issues/430), [#431](https://github.com/saworbit/hammerforge/issues/431), PR [#453](https://github.com/saworbit/hammerforge/pull/453))
- **13 Sep** Saving a level keeps heightmaps at full precision; every save and undo used to round them to 8 bits. (issue [#445](https://github.com/saworbit/hammerforge/issues/445), PR [#452](https://github.com/saworbit/hammerforge/pull/452))
- **12 Sep** Rebinding a shortcut onto a chord another action uses is flagged; the other action used to become unreachable in silence. (issue [#410](https://github.com/saworbit/hammerforge/issues/410), PR [#428](https://github.com/saworbit/hammerforge/pull/428))
- **12 Sep** Toggling the measure tool's align off keeps the chosen reference ruler; pressing A again used to pick the newest one. (issues [#405](https://github.com/saworbit/hammerforge/issues/405), [#411](https://github.com/saworbit/hammerforge/issues/411), PR [#427](https://github.com/saworbit/hammerforge/pull/427))
- **12 Sep** A material library with missing materials says which on load, and the status board no longer calls it an empty palette. (issues [#414](https://github.com/saworbit/hammerforge/issues/414), [#415](https://github.com/saworbit/hammerforge/issues/415), PR [#426](https://github.com/saworbit/hammerforge/pull/426))
- **12 Sep** A painted face keeps its normal map, UV scale and other material settings, and a shader material is no longer replaced. (issues [#412](https://github.com/saworbit/hammerforge/issues/412), [#413](https://github.com/saworbit/hammerforge/issues/413), PR [#425](https://github.com/saworbit/hammerforge/pull/425))
- **12 Sep** A level with more texture than the atlas holds bakes, with the overflow on its own surfaces; the atlas used to fail outright. (issue [#416](https://github.com/saworbit/hammerforge/issues/416), PR [#424](https://github.com/saworbit/hammerforge/pull/424))
- **12 Sep** User preferences replace a bad value with the default and save atomically; a crash mid-write used to reset them all. (issues [#408](https://github.com/saworbit/hammerforge/issues/408), [#409](https://github.com/saworbit/hammerforge/issues/409), PR [#423](https://github.com/saworbit/hammerforge/pull/423))
- **12 Sep** An entity input named QueueFree no longer deletes its target, and one malformed entity no longer drops its subtree from the wiring. (issues [#406](https://github.com/saworbit/hammerforge/issues/406), [#407](https://github.com/saworbit/hammerforge/issues/407), PR [#422](https://github.com/saworbit/hammerforge/pull/422))
- **12 Sep** Decals are saved with the level and placing one can be undone; they used to vanish on save and reload. (issues [#403](https://github.com/saworbit/hammerforge/issues/403), [#404](https://github.com/saworbit/hammerforge/issues/404), PR [#421](https://github.com/saworbit/hammerforge/pull/421))
- **12 Sep** The extrude preview is no longer a brush in the level, sits on the face under the cursor, and extrusions get unique ids. (issues [#400](https://github.com/saworbit/hammerforge/issues/400), [#401](https://github.com/saworbit/hammerforge/issues/401), [#402](https://github.com/saworbit/hammerforge/issues/402), PR [#420](https://github.com/saworbit/hammerforge/pull/420))
- **12 Sep** The polygon tool refuses collinear or repeated points instead of building a zero-volume brush. (issues [#398](https://github.com/saworbit/hammerforge/issues/398), [#399](https://github.com/saworbit/hammerforge/issues/399), PR [#419](https://github.com/saworbit/hammerforge/pull/419))
- **12 Sep** Path tool brushes are wound the right way out, and saved levels with inside-out corridors are repaired on load. (issue [#397](https://github.com/saworbit/hammerforge/issues/397), PR [#418](https://github.com/saworbit/hammerforge/pull/418))
- **12 Sep** A vertex move that bends a face out of plane is refused; it used to commit and export a different solid. (issue [#364](https://github.com/saworbit/hammerforge/issues/364), PR [#395](https://github.com/saworbit/hammerforge/pull/395))
- **12 Sep** Changing a bake setting marks the bake stale; turning off `bake_visible_only` and baking again used to keep the old result. (issue [#376](https://github.com/saworbit/hammerforge/issues/376), PR [#394](https://github.com/saworbit/hammerforge/pull/394))
- **12 Sep** Merging an additive brush with a subtractive one is refused on redo too; a redo could turn a doorway into a wall. (issue [#383](https://github.com/saworbit/hammerforge/issues/383), PR [#392](https://github.com/saworbit/hammerforge/pull/392))
- **12 Sep** Bake and grid number settings are clamped, including on load; a NaN `grid_snap` in a `.hflevel` turned snapping off everywhere. (issue [#373](https://github.com/saworbit/hammerforge/issues/373), PR [#391](https://github.com/saworbit/hammerforge/pull/391))
- **12 Sep** A cordon with a negative size is read as a real box; it used to bake an empty level and report success. (issue [#377](https://github.com/saworbit/hammerforge/issues/377), PR [#391](https://github.com/saworbit/hammerforge/pull/391))
- **12 Sep** The validator catches a brush whose size is not a number, and auto fix restores the default size. (issue [#371](https://github.com/saworbit/hammerforge/issues/371), PR [#390](https://github.com/saworbit/hammerforge/pull/390))
- **12 Sep** The validator reports brushes with no faces, bowed faces and NaN vertices, and auto fix repairs what it can. (issue [#372](https://github.com/saworbit/hammerforge/issues/372), PR [#390](https://github.com/saworbit/hammerforge/pull/390))
- **12 Sep** A group name of only whitespace is refused and names are trimmed; Arch and Arch with a trailing space were two groups. (issue [#374](https://github.com/saworbit/hammerforge/issues/374), PR [#389](https://github.com/saworbit/hammerforge/pull/389))
- **12 Sep** An `entities.json` with a wrong-type entities key falls back to the built-in classes; it used to leave no entity definitions. (issue [#380](https://github.com/saworbit/hammerforge/issues/380), PR [#389](https://github.com/saworbit/hammerforge/pull/389))
- **12 Sep** A whitespace-only entity classname is refused and classnames are trimmed; a classname defined twice in a file now warns. (issue [#381](https://github.com/saworbit/hammerforge/issues/381), PR [#389](https://github.com/saworbit/hammerforge/pull/389))
- **12 Sep** A placed prefab no longer brings visgroup names the level never registered; those brushes could not be shown or hidden. (issue [#368](https://github.com/saworbit/hammerforge/issues/368), PR [#388](https://github.com/saworbit/hammerforge/pull/388))
- **12 Sep** A prefab restore no longer reissues a live instance id; the next placement used to take over an older prefab's id. (issue [#369](https://github.com/saworbit/hammerforge/issues/369), PR [#388](https://github.com/saworbit/hammerforge/pull/388))
- **12 Sep** A malformed `.hfprefab` no longer freezes the brush list, entity list and validation badge for the rest of the session. (issue [#370](https://github.com/saworbit/hammerforge/issues/370), PR [#388](https://github.com/saworbit/hammerforge/pull/388))
- **12 Sep** A non-finite vertex move is refused; it used to write NaN into the face data and spread through clip and carve. (issue [#365](https://github.com/saworbit/hammerforge/issues/365), PR [#387](https://github.com/saworbit/hammerforge/pull/387))
- **12 Sep** Merging every vertex of a brush is refused; it used to leave an invisible brush with no faces. (issue [#366](https://github.com/saworbit/hammerforge/issues/366), PR [#387](https://github.com/saworbit/hammerforge/pull/387))
- **12 Sep** Splitting an edge no longer gives a wall a floor's normal, which the bake and `.map` export read. (issue [#367](https://github.com/saworbit/hammerforge/issues/367), PR [#387](https://github.com/saworbit/hammerforge/pull/387))
- **12 Sep** Resizing a brush handles zero, negative and NaN sizes the way creating one does; a negative size built it inside out. (issue [#378](https://github.com/saworbit/hammerforge/issues/378), PR [#386](https://github.com/saworbit/hammerforge/pull/386))
- **12 Sep** A non-finite nudge offset is refused; it used to send the selection to a position with nothing to click. (issue [#379](https://github.com/saworbit/hammerforge/issues/379), PR [#386](https://github.com/saworbit/hammerforge/pull/386))
- **12 Sep** An array refuses an offset, spacing, step, rise or pivot that is not a number; every copy used to land at a NaN position. (issue [#382](https://github.com/saworbit/hammerforge/issues/382), PR [#386](https://github.com/saworbit/hammerforge/pull/386))
- **11 Sep** A grid array with a negative axis count is refused; it used to be clamped and built without a word. (issue [#346](https://github.com/saworbit/hammerforge/issues/346), PR [#362](https://github.com/saworbit/hammerforge/pull/362))
- **11 Sep** A visgroup name of only whitespace is refused and names are trimmed; it used to show as a blank row. (issue [#349](https://github.com/saworbit/hammerforge/issues/349), PR [#362](https://github.com/saworbit/hammerforge/pull/362))
- **11 Sep** The heightmap scale and terrain layer height refuse NaN, and a zero scale gets a floor; a NaN put the whole layer nowhere. (issue [#350](https://github.com/saworbit/hammerforge/issues/350), PR [#361](https://github.com/saworbit/hammerforge/pull/361))
- **11 Sep** Region size and memory budget are clamped at both ends; a huge region size left streaming on but with nothing it could evict. (issue [#352](https://github.com/saworbit/hammerforge/issues/352), PR [#361](https://github.com/saworbit/hammerforge/pull/361))
- **11 Sep** A malformed `.hflevel` is refused with a reason and the level left as it was; it used to empty the level first. (issue [#347](https://github.com/saworbit/hammerforge/issues/347), PR [#360](https://github.com/saworbit/hammerforge/pull/360))
- **11 Sep** A brush with a NaN size is refused on load and undo; it used to poison the level bounds and the saved file for good. (issue [#348](https://github.com/saworbit/hammerforge/issues/348), PR [#360](https://github.com/saworbit/hammerforge/pull/360))
- **11 Sep** A duplicated wired entity takes the next free name, `door_1` becomes `door_2`; both copies used to answer to one name. (issue [#341](https://github.com/saworbit/hammerforge/issues/341), PR [#359](https://github.com/saworbit/hammerforge/pull/359))
- **11 Sep** Entity outputs refuse a blank name or a NaN delay, and `.map` import reports the wiring lines it drops instead of losing them silently. (issue [#342](https://github.com/saworbit/hammerforge/issues/342), PR [#359](https://github.com/saworbit/hammerforge/pull/359))
- **11 Sep** A face's material slot must exist in the palette; an out-of-range slot used to export as `__default`. (issue [#343](https://github.com/saworbit/hammerforge/issues/343), PR [#358](https://github.com/saworbit/hammerforge/pull/358))
- **11 Sep** Face UV settings refuse a non-finite value or a zero scale; either one broke the face's texture and survived the save. (issue [#344](https://github.com/saworbit/hammerforge/issues/344), PR [#358](https://github.com/saworbit/hammerforge/pull/358))
- **11 Sep** A face only accepts a known UV projection, even from a file; an unknown one showed in no dock control and exported unpredictably. (issue [#345](https://github.com/saworbit/hammerforge/issues/345), PR [#358](https://github.com/saworbit/hammerforge/pull/358))
- **11 Sep** A bevel radius of zero or less is refused; it used to build a tiny bevel whose cap faced into the solid. (issue [#330](https://github.com/saworbit/hammerforge/issues/330), PR [#357](https://github.com/saworbit/hammerforge/pull/357))
- **11 Sep** Inset refuses a NaN value or a zero distance, and a recessed inset no longer turns its walls inside out. (issues [#339](https://github.com/saworbit/hammerforge/issues/339), [#340](https://github.com/saworbit/hammerforge/issues/340), PR [#357](https://github.com/saworbit/hammerforge/pull/357))
- **11 Sep** Generators refuse NaN settings instead of building a structure out of broken brushes and reporting success. (issue [#336](https://github.com/saworbit/hammerforge/issues/336), PR [#356](https://github.com/saworbit/hammerforge/pull/356))
- **11 Sep** Generator sizes and counts are held to the dock's maximums everywhere; an arch could be asked for 129,000 segments. (issues [#337](https://github.com/saworbit/hammerforge/issues/337), [#338](https://github.com/saworbit/hammerforge/issues/338), PR [#356](https://github.com/saworbit/hammerforge/pull/356))
- **11 Sep** Texture lock keeps textures upright on the walls of a rotated brush; a yaw used to leave four box faces a quarter turn out. (issue [#333](https://github.com/saworbit/hammerforge/issues/333), PR [#355](https://github.com/saworbit/hammerforge/pull/355))
- **11 Sep** UV rotation wraps into one turn, so four 90-degree turns read 0 again; exported `.map` files used to say -360. (issue [#334](https://github.com/saworbit/hammerforge/issues/334), PR [#355](https://github.com/saworbit/hammerforge/pull/355))
- **11 Sep** Rotate and flip refuse a NaN angle or pivot that used to leave a brush permanently broken in the bake and the saved file. (issue [#335](https://github.com/saworbit/hammerforge/issues/335), PR [#355](https://github.com/saworbit/hammerforge/pull/355))
- **11 Sep** Valve 220 `.map` export writes texture axes that lie in each face; four of a box's six faces came out degenerate. (issue [#317](https://github.com/saworbit/hammerforge/issues/317), PR [#327](https://github.com/saworbit/hammerforge/pull/327))
- **11 Sep** Two paint layers cannot be renamed to the same name; the paint target list used to show two identical rows. (issue [#321](https://github.com/saworbit/hammerforge/issues/321), PR [#326](https://github.com/saworbit/hammerforge/pull/326))
- **11 Sep** Deleting a hidden visgroup shows its members again; they used to stay invisible with no way to show them. (issue [#316](https://github.com/saworbit/hammerforge/issues/316), PR [#325](https://github.com/saworbit/hammerforge/pull/325))
- **11 Sep** Bevel, `.map` import and displacement tools refuse values they cannot use; a second displacement create used to wipe the terrain. (issues [#315](https://github.com/saworbit/hammerforge/issues/315), [#318](https://github.com/saworbit/hammerforge/issues/318), [#319](https://github.com/saworbit/hammerforge/issues/319), [#320](https://github.com/saworbit/hammerforge/issues/320), PR [#324](https://github.com/saworbit/hammerforge/pull/324))
- **11 Sep** Prisms, octahedrons, dodecahedrons and icosahedrons are no longer inside out at bake and export; saved levels are fixed on load. (issue [#313](https://github.com/saworbit/hammerforge/issues/313), PR [#323](https://github.com/saworbit/hammerforge/pull/323))
- **11 Sep** Bevels chamfer the corner and keep the brush convex; they used to scoop it out and add back-facing faces. (issue [#314](https://github.com/saworbit/hammerforge/issues/314), PR [#323](https://github.com/saworbit/hammerforge/pull/323))
- **11 Sep** Erasing paint frees its memory, so painting and erasing an area no longer leaves the level file bigger. (issue [#301](https://github.com/saworbit/hammerforge/issues/301), PR [#312](https://github.com/saworbit/hammerforge/pull/312))
- **11 Sep** A zero or negative brush size is made positive on creation; a negative one used to turn the brush inside out at bake. (issue [#289](https://github.com/saworbit/hammerforge/issues/289), PR [#311](https://github.com/saworbit/hammerforge/pull/311))
- **11 Sep** The bake dry run counts only brushes the bake will take, respecting the cordon and Bake Visible Only. (issue [#295](https://github.com/saworbit/hammerforge/issues/295), PR [#310](https://github.com/saworbit/hammerforge/pull/310))
- **11 Sep** Renaming a visgroup to a name already in use is refused; it used to merge the two and lose one's record. (issue [#296](https://github.com/saworbit/hammerforge/issues/296), PR [#309](https://github.com/saworbit/hammerforge/pull/309))
- **11 Sep** Typing a size mid-drag works on the numeric keypad; keypad digits were ignored while keypad Enter still committed. (issue [#297](https://github.com/saworbit/hammerforge/issues/297), PR [#308](https://github.com/saworbit/hammerforge/pull/308))
- **11 Sep** A connection names its source by the name it is addressed by; wired brush entities used to show as triggering nothing. (issue [#288](https://github.com/saworbit/hammerforge/issues/288), PR [#307](https://github.com/saworbit/hammerforge/pull/307))
- **11 Sep** `.map` export carries entity names and I/O outputs, and import reads them back; wired levels used to export inert. (issue [#287](https://github.com/saworbit/hammerforge/issues/287), PR [#307](https://github.com/saworbit/hammerforge/pull/307))
- **11 Sep** A bad value in a displacement, keymap, generator setting or preset file is reported and skipped; the keymap used to error on every key. (issues [#290](https://github.com/saworbit/hammerforge/issues/290), [#292](https://github.com/saworbit/hammerforge/issues/292), [#293](https://github.com/saworbit/hammerforge/issues/293), [#294](https://github.com/saworbit/hammerforge/issues/294), PR [#306](https://github.com/saworbit/hammerforge/pull/306))
- **11 Sep** `.map` export writes each face's material name instead of `__default`, and import maps names back to palette slots. (issue [#286](https://github.com/saworbit/hammerforge/issues/286), PR [#305](https://github.com/saworbit/hammerforge/pull/305))
- **11 Sep** A cylinder exports one outward plane per side and cap; it used to write duplicate planes that compilers called degenerate. (issue [#291](https://github.com/saworbit/hammerforge/issues/291), PR [#305](https://github.com/saworbit/hammerforge/pull/305))
- **11 Sep** A bad array count leaves the array standing; typing 0 used to delete the copies and make the array unreachable. (issue [#299](https://github.com/saworbit/hammerforge/issues/299), PR [#304](https://github.com/saworbit/hammerforge/pull/304))
- **11 Sep** The 256-copy limit holds for grid arrays and updates too; a 12-cubed grid used to build 1,728 brushes. (issue [#300](https://github.com/saworbit/hammerforge/issues/300), PR [#304](https://github.com/saworbit/hammerforge/pull/304))
- **11 Sep** Removing a palette material keeps every other face on its own material; faces above it used to shift to the next one. (issue [#285](https://github.com/saworbit/hammerforge/issues/285), PR [#303](https://github.com/saworbit/hammerforge/pull/303))
- **11 Sep** Refresh Prototypes adds only missing materials; a second click used to double the palette to 300 entries. (issue [#298](https://github.com/saworbit/hammerforge/issues/298), PR [#303](https://github.com/saworbit/hammerforge/pull/303))
- **11 Sep** Undo puts back a palette material edited after the snapshot; snapshots used to share the live palette and selection. (issue [#282](https://github.com/saworbit/hammerforge/issues/282), PR [#302](https://github.com/saworbit/hammerforge/pull/302))
- **11 Sep** Loading a `.hflevel` restores its material palette again; faces used to point into the editor's old palette. (issue [#283](https://github.com/saworbit/hammerforge/issues/283), PR [#302](https://github.com/saworbit/hammerforge/pull/302))
- **11 Sep** Terrain slot textures, UV scales and tints survive loading a `.hflevel`; they used to reset to defaults. (issue [#284](https://github.com/saworbit/hammerforge/issues/284), PR [#302](https://github.com/saworbit/hammerforge/pull/302))
- **9 Sep** Placing a prefab wires each copy's outputs inside the new instance; one could stay aimed at the entities it was built from. (PR [#262](https://github.com/saworbit/hammerforge/pull/262))
- **9 Sep** Deleting a named entity also removes connections aimed at its authored name; they used to dangle and could hit a reused name. (PR [#258](https://github.com/saworbit/hammerforge/pull/258))
- **9 Sep** CSG nodes away from the origin bake their mesh and collision in place; both used to land at the origin. (PR [#255](https://github.com/saworbit/hammerforge/pull/255))
- **9 Sep** Custom brushes, such as vertex-edited, bevelled or imported ones, bake in their real shape; they used to bake as boxes. (PR [#254](https://github.com/saworbit/hammerforge/pull/254))
- **9 Sep** A point entity keeps its authored name through save, undo and duplicate; outputs aimed at it used to fire at nothing. (PR [#253](https://github.com/saworbit/hammerforge/pull/253))
- **9 Sep** The entity wiring overlay is removed when a scene closes or the plugin reloads; a copy used to be left behind each time. (PR [#248](https://github.com/saworbit/hammerforge/pull/248))
- **9 Sep** Tilted brushes import from `.map` as closed solids; cylinders, ramps, wedges and turned boxes used to arrive as loose triangles. (PR [#247](https://github.com/saworbit/hammerforge/pull/247))
- **9 Sep** Cutters are left out of `.map` exports; a doorway carved into a wall used to export with a solid block standing in it. (PR [#246](https://github.com/saworbit/hammerforge/pull/246))
- **9 Sep** Baking with the LevelRoot moved or turned puts geometry where you built it; the root's offset and rotation used to be applied twice. (PR [#226](https://github.com/saworbit/hammerforge/pull/226))
- **9 Sep** Create Radial Array can be undone; Ctrl+Z used to skip past it and leave the copies in the scene. (PR [#225](https://github.com/saworbit/hammerforge/pull/225))
- **9 Sep** New brushes and restored entities land where they belong with the LevelRoot moved; they used to shift by the root's offset. (PR [#225](https://github.com/saworbit/hammerforge/pull/225))
- **9 Sep** New brushes are drawn on the grid shown on screen; they used to land at height zero, and an upright axis-locked grid could not start a drag. (PR [#219](https://github.com/saworbit/hammerforge/pull/219))
- **9 Sep** Cordon, entity wire, vertex/edge handle and prefab ghost overlays draw in place with the LevelRoot moved; vertex editing was unusable. (PR [#218](https://github.com/saworbit/hammerforge/pull/218))
- **9 Sep** Hollow, Carve, Clip and Subtract previews draw on the brush with the LevelRoot moved or turned; the clip plane used to be drawn far off. (PR [#217](https://github.com/saworbit/hammerforge/pull/217))
- **9 Sep** Nudging one piece of a moved structure no longer sends the whole structure back to where it was created on the next Update. (PR [#214](https://github.com/saworbit/hammerforge/pull/214))
- **8 Sep** Entity property values with quotes or `//` read back from `.map` whole; they used to be cut short without an error. (PR [#208](https://github.com/saworbit/hammerforge/pull/208))
- **8 Sep** Clip to Face Plane can be undone, works in the order the guide gives, and runs from Alt+Shift+X in the viewport. (PR [#207](https://github.com/saworbit/hammerforge/pull/207))
- **8 Sep** Reset Rotation keeps scale set with Godot's own gizmo; a scaled box used to lose its scale. (PR [#207](https://github.com/saworbit/hammerforge/pull/207))
- **8 Sep** Flip carries per-face materials, UVs and paint with the mirrored faces; they used to stay on the side they started. (PR [#207](https://github.com/saworbit/hammerforge/pull/207))
- **8 Sep** Redo after quick rotates or nudges redoes the whole run; three presses undid 45 degrees and redid 15. (PR [#207](https://github.com/saworbit/hammerforge/pull/207))
- **8 Sep** Structure settings that cannot build say why instead of reporting Created, and Ctrl+Shift+A runs Create Structure from the viewport. (PR [#207](https://github.com/saworbit/hammerforge/pull/207))
- **8 Sep** Updating a structure keeps its painted faces, and warns first when a rebuild would drop some; paint used to be lost silently. (PR [#207](https://github.com/saworbit/hammerforge/pull/207))
- **8 Sep** Importing a `.map` or loading an example clears the old level's structure records; they used to leak into undo and every save. (PR [#207](https://github.com/saworbit/hammerforge/pull/207))
- **8 Sep** Open stairs and open spiral stairs sit on the point they are placed on; they used to float four units high. (PR [#207](https://github.com/saworbit/hammerforge/pull/207))
- **8 Sep** Carve finds a rotated brush wherever it reaches; a carver on the far end of a turned brush used to cut nothing. (PR [#207](https://github.com/saworbit/hammerforge/pull/207))
- **8 Sep** Texture lock allows for UV rotation when a brush moves, so the texture stays pinned instead of drifting along the wrong axes. (issue [#141](https://github.com/saworbit/hammerforge/issues/141), PR [#207](https://github.com/saworbit/hammerforge/pull/207))
- **8 Sep** Rebuilding a structure deletes only its own pieces, never a neighbouring brush that was handed one of its old ids. (PR [#188](https://github.com/saworbit/hammerforge/pull/188))
- **8 Sep** Hollow works out which side is inside instead of trusting face normals; a sphere used to report no room inside it. (PR [#187](https://github.com/saworbit/hammerforge/pull/187))
- **8 Sep** Clip to Convex builds faces the right way out; every brush it repaired used to bake inside out. (PR [#186](https://github.com/saworbit/hammerforge/pull/186))
- **7 Sep** Entity I/O connections and names on brushes survive save, autosave, undo and duplicate; they used to be deleted silently. (issue [#149](https://github.com/saworbit/hammerforge/issues/149), PR [#184](https://github.com/saworbit/hammerforge/pull/184))
- **7 Sep** Baking keeps trigger and detail brush names, so I/O wired to them fires; they used to be renamed Trigger_0 and FuncDetail_0. (issue [#140](https://github.com/saworbit/hammerforge/issues/140), PR [#184](https://github.com/saworbit/hammerforge/pull/184))
- **7 Sep** Baked `func_detail` collision bodies sit at their brush; they used to sit at the world origin with only the shape moved. (issue [#158](https://github.com/saworbit/hammerforge/issues/158), PR [#184](https://github.com/saworbit/hammerforge/pull/184))
- **7 Sep** I/O events fired by an entity's authored name reach it at runtime; they used to be dropped silently. (issue [#151](https://github.com/saworbit/hammerforge/issues/151), PR [#184](https://github.com/saworbit/hammerforge/pull/184))
- **7 Sep** Batched edits tell listeners which brushes were added, removed or changed; deleted brushes used to be reported as selected. (issue [#139](https://github.com/saworbit/hammerforge/issues/139), PR [#184](https://github.com/saworbit/hammerforge/pull/184))
- **7 Sep** The `entity_added` and `entity_removed` signals fire when entities enter or leave a level; they were promised but never emitted. (issue [#150](https://github.com/saworbit/hammerforge/issues/150), PR [#184](https://github.com/saworbit/hammerforge/pull/184))
- **7 Sep** Custom, beveled, carved, polygon and prism brushes export to and import from `.map` the right way out; compilers used to reject them. (issue [#148](https://github.com/saworbit/hammerforge/issues/148), PR [#184](https://github.com/saworbit/hammerforge/pull/184))
- **7 Sep** Importing a file that is not a `.map` is refused before the level is touched; it used to clear the level and report success. (issue [#174](https://github.com/saworbit/hammerforge/issues/174), PR [#184](https://github.com/saworbit/hammerforge/pull/184))
- **7 Sep** Baking with Generate LODs on works; it used to stop the bake with an error. (issue [#138](https://github.com/saworbit/hammerforge/issues/138), PR [#184](https://github.com/saworbit/hammerforge/pull/184))
- **7 Sep** The material atlas builds mipmaps, so distant atlas surfaces no longer shimmer. (issue [#157](https://github.com/saworbit/hammerforge/issues/157), PR [#184](https://github.com/saworbit/hammerforge/pull/184))
- **7 Sep** Saves to the same file finish in the order they were made; an older save could finish last and stay on disk. (issue [#51](https://github.com/saworbit/hammerforge/issues/51), PR [#184](https://github.com/saworbit/hammerforge/pull/184))
- **7 Sep** Painting across a large level saves each region before unloading it; moving on used to throw away the painting behind you. (issue [#172](https://github.com/saworbit/hammerforge/issues/172), PR [#184](https://github.com/saworbit/hammerforge/pull/184))
- **7 Sep** A level save stops and says so when a paint region file fails to write; it used to report success with the files missing. (issue [#173](https://github.com/saworbit/hammerforge/issues/173), PR [#184](https://github.com/saworbit/hammerforge/pull/184))
- **7 Sep** Custom point entities from `res://hammerforge_entities.json` appear in the Objects palette, and brush entities no longer do. (issue [#175](https://github.com/saworbit/hammerforge/issues/175), PR [#184](https://github.com/saworbit/hammerforge/pull/184))
- **7 Sep** Hovering down the undo history no longer makes the dock jump; the hover preview used to resize the panel on every row. (issue [#142](https://github.com/saworbit/hammerforge/issues/142), PR [#184](https://github.com/saworbit/hammerforge/pull/184))
- **7 Sep** The contextual toolbar wraps to fit a narrow viewport; it used to run off both sides with its end buttons out of reach. (PR [#171](https://github.com/saworbit/hammerforge/pull/171))
- **7 Sep** Command palette keybindings show in full; Ctrl+Shift+Enter used to show as Ctr. (PR [#170](https://github.com/saworbit/hammerforge/pull/170))
- **7 Sep** Viewport overlays float over the viewport instead of taking toolbar space; opening the command palette used to squeeze the viewport. (PR [#168](https://github.com/saworbit/hammerforge/pull/168))
- **7 Sep** The 3D toolbar keeps one height and the status strip one width, so the viewport and toolbar stop shifting as hints change. (PR [#167](https://github.com/saworbit/hammerforge/pull/167))
- **7 Sep** Dragging out a box no longer makes one side flicker; the drag used to hit its own preview. (PR [#167](https://github.com/saworbit/hammerforge/pull/167))

#### Behind the scenes

- **12 Sep** The uncalled material usage tracker is removed; it counted preview tints, so it would have called painted materials unused. (issue [#375](https://github.com/saworbit/hammerforge/issues/375), PR [#393](https://github.com/saworbit/hammerforge/pull/393))
- **10 Sep** CI refuses a `project.godot` that enables any plugin besides HammerForge or registers an autoload. (PR [#281](https://github.com/saworbit/hammerforge/pull/281))
- **10 Sep** The repo no longer bundles or enables the Godot MCP editor bridge; `addons/` is allowlisted so a local bridge stays untracked. (issue [#277](https://github.com/saworbit/hammerforge/issues/277), PR [#280](https://github.com/saworbit/hammerforge/pull/280))
- **10 Sep** `tools/wait_for_ci.py` waits on a pull request's head commit rather than the branch, so a stale run is never read as a pass. (PR [#272](https://github.com/saworbit/hammerforge/pull/272))
- **9 Sep** The six preview overlays share one base class, `HFPreviewSystem`, instead of six copies of the same container code. (PR [#238](https://github.com/saworbit/hammerforge/pull/238))
- **9 Sep** `tools/check_placement_order.py` fails the build when code sets a node's global position before parenting it, a mistake fixed six times. (PR [#227](https://github.com/saworbit/hammerforge/pull/227))
- **8 Sep** The guide no longer says Hollow refuses a rotated brush or sends you to Reset Rotation to fix it. (PR [#207](https://github.com/saworbit/hammerforge/pull/207))
- **8 Sep** The Clip to Face Plane walkthrough says to select the brushes before the face, the only order that works. (PR [#207](https://github.com/saworbit/hammerforge/pull/207))
- **8 Sep** The guide drops Reset Rotation as the way back to Hollow, Clip and Carve and covers paint surviving a structure rebuild. (PR [#207](https://github.com/saworbit/hammerforge/pull/207))
- **8 Sep** Tests measure every stairs, spiral stairs and dome panel for planarity, closure, convexity and outward winding. (PR [#189](https://github.com/saworbit/hammerforge/pull/189))
- **8 Sep** Two test files with 121 tests that failed to load run again, and the suite now fails when any test file will not load. (PR [#189](https://github.com/saworbit/hammerforge/pull/189))
- **8 Sep** Tests cover live generator records through undo and save, materials kept across rebuilds, and rebuilt pieces baking outward. (PR [#188](https://github.com/saworbit/hammerforge/pull/188))
- **8 Sep** Tests cover arch closure, convexity and dimensions, helix rise, and outward winding at bake. (PR [#187](https://github.com/saworbit/hammerforge/pull/187))
- **8 Sep** Cutting gets 96 tests, including carve's first suite: volume, closure, outward winding at bake and awkward planes. (PR [#186](https://github.com/saworbit/hammerforge/pull/186))
- **8 Sep** Tests cover the rotate and flip maths and prove mirrored geometry still faces outward at bake. (PR [#185](https://github.com/saworbit/hammerforge/pull/185))
- **8 Sep** A UV rotation helper moved from the brush system to the transform system, where it finally has a caller. (PR [#185](https://github.com/saworbit/hammerforge/pull/185))
- **8 Sep** Nudge and the three transform actions share one selection classifier instead of repeating it. (PR [#185](https://github.com/saworbit/hammerforge/pull/185))

### Week of 31 Aug 2026

#### Added

- **5 Sep** The HammerForge Console opens beside 2D, 3D and Script, with Status, Controls and Log tabs. (PR [#108](https://github.com/saworbit/hammerforge/pull/108))
- **5 Sep** A status lamp in the 3D viewport toolbar shows the Console's overall state and opens the board on a click. (PR [#108](https://github.com/saworbit/hammerforge/pull/108))

#### Changed

- **6 Sep** Snapping caches each brush's geometry; an all-non-box level's snap cost per mouse move fell from 15 ms to 3.5 ms. (issue [#122](https://github.com/saworbit/hammerforge/issues/122), PR [#133](https://github.com/saworbit/hammerforge/pull/133))
- **6 Sep** Snapping while dragging is faster on levels with non-box brushes; an all-non-box level went from 77 ms to 15 ms per mouse move. (issue [#122](https://github.com/saworbit/hammerforge/issues/122), PR [#129](https://github.com/saworbit/hammerforge/pull/129))
- **5 Sep** The power-user overlay toast names both the Console's Controls tab and the dock's Test -> Settings, and the guide says they are opt-in. (PR [#110](https://github.com/saworbit/hammerforge/pull/110))
- **5 Sep** HammerForge has its own icon in the main-screen switcher, and its left dock tab says HammerForge instead of Dock. (PR [#108](https://github.com/saworbit/hammerforge/pull/108))
- **5 Sep** Warnings and level messages also go to the Console's Log tab, so a failed bake can be read after its toast fades. (PR [#108](https://github.com/saworbit/hammerforge/pull/108))

#### Fixed

- **6 Sep** The live subtract preview refreshes as brushes are moved, painted or edited, not only when one is added or removed. (PR [#131](https://github.com/saworbit/hammerforge/pull/131))
- **6 Sep** Box faces export to `.map` with their own texture and UV settings; each used to carry another face's. (issue [#113](https://github.com/saworbit/hammerforge/issues/113), PR [#129](https://github.com/saworbit/hammerforge/pull/129))
- **6 Sep** A bevel's far corner cap faces outward; it used to face into the brush and break CSG and collision. (issue [#112](https://github.com/saworbit/hammerforge/issues/112), PR [#129](https://github.com/saworbit/hammerforge/pull/129))
- **6 Sep** Clip and Hollow previews only draw for brushes the tools accept; a cylinder or rotated box used to preview, then fail. (issue [#116](https://github.com/saworbit/hammerforge/issues/116), PR [#129](https://github.com/saworbit/hammerforge/pull/129))
- **6 Sep** Play from Camera leaves no step on the undo stack; Redo used to move the spawn to the camera for good. (issue [#114](https://github.com/saworbit/hammerforge/issues/114), PR [#129](https://github.com/saworbit/hammerforge/pull/129))
- **5 Sep** The shortcut HUD shows one line in its own space; it used to draw over the viewport and the context toolbar. (PR [#108](https://github.com/saworbit/hammerforge/pull/108))
- **5 Sep** Fractional grid snaps show their value; they used to show `Grid: %g` and raise an engine error. (PR [#108](https://github.com/saworbit/hammerforge/pull/108))

#### Behind the scenes

- **6 Sep** CI runs `gdformat` over `tests/` as well; a string it could not parse had gone unnoticed there. (issue [#115](https://github.com/saworbit/hammerforge/issues/115), PR [#129](https://github.com/saworbit/hammerforge/pull/129))
- **6 Sep** The carve, clip, hollow and subtract previews share one box outline instead of four identical copies. (issue [#121](https://github.com/saworbit/hammerforge/issues/121), PR [#129](https://github.com/saworbit/hammerforge/pull/129))
- **6 Sep** The path and polygon tools share one raycast instead of carrying identical copies of two. (issue [#124](https://github.com/saworbit/hammerforge/issues/124), PR [#129](https://github.com/saworbit/hammerforge/pull/129))
- **6 Sep** Brush lookups call LevelRoot directly and face keys come from one function instead of three. (issue [#123](https://github.com/saworbit/hammerforge/issues/123), PR [#129](https://github.com/saworbit/hammerforge/pull/129))
- **5 Sep** Tests cover the Console's severity thresholds and log buffer, and check every Controls switch names a real setting. (PR [#108](https://github.com/saworbit/hammerforge/pull/108))
- **5 Sep** `tools/hf_console_preview.gd` renders the Console's three tabs to PNGs, so a layout change can be judged without the editor. (PR [#108](https://github.com/saworbit/hammerforge/pull/108))
- **5 Sep** `docs/brand/build.py` also writes the addon's lockups and editor mark, so the editor's icons cannot drift from the brand set. (PR [#108](https://github.com/saworbit/hammerforge/pull/108))

## [0.3.0] - 2026-09-03

**Highlights**

- Selection and the camera follow Godot's rules: right-mouse look always works, and clicks hit the faces you can see rather than a bounding box.
- Bake Changed catches every edit, repeated bakes replace the old result instead of piling up, and Test Level wires entity I/O by default.
- New in the editor: a starter level in one click, snap to edge and to perpendicular, extrude keys, a Space context menu, and a radial menu behind Power-user overlays.
- Surface painting works again, and material atlasing keeps normal, roughness, metallic and emission maps.
- Behind the scenes, the dock and plugin are split into focused modules.

The long write-ups, as first written: [changelog/0.3.0.md](changelog/0.3.0.md)

### Week of 31 Aug 2026

#### Added

- **3 Sep** Material atlasing keeps normal, roughness, metallic and emission maps, and warns about a map it cannot pack faithfully instead of dropping it. (issue [#24](https://github.com/saworbit/hammerforge/issues/24), PR [#64](https://github.com/saworbit/hammerforge/pull/64))

#### Changed

- **3 Sep** Material atlas gutters fill 11 times faster on a 128px tile, which matters now that each PBR map builds its own atlas. (PR [#64](https://github.com/saworbit/hammerforge/pull/64))
- **3 Sep** Painted faces cache their composite, so each paint sample no longer recomposites every painted face of the brush. (issue [#39](https://github.com/saworbit/hammerforge/issues/39), PR [#63](https://github.com/saworbit/hammerforge/pull/63))
- **3 Sep** Exported games load only the brush, entity, bake, paint and file core, skipping HammerForge's editor-only tools. (issue [#21](https://github.com/saworbit/hammerforge/issues/21), commit [6e0b740](https://github.com/saworbit/hammerforge/commit/6e0b7402c4cd24d1bc0c873e081444306d5b6447))

#### Fixed

- **3 Sep** HammerForge warnings print on their own; each used to bring a spurious "Method/function failed. Returning: Variant()" engine error. (PR [#64](https://github.com/saworbit/hammerforge/pull/64))
- **3 Sep** Surface painting works again; every stroke was silently thrown away. (PR [#63](https://github.com/saworbit/hammerforge/pull/63))
- **3 Sep** Painted face previews leave the source texture untouched and can read VRAM-compressed textures; they used to resize the original in place. (PR [#63](https://github.com/saworbit/hammerforge/pull/63))
- **3 Sep** Polygon and Path start on the visible brush surface under the cursor, and every point applies all enabled snap modes. (issue [#65](https://github.com/saworbit/hammerforge/issues/65), commit [6e0b740](https://github.com/saworbit/hammerforge/commit/6e0b7402c4cd24d1bc0c873e081444306d5b6447))
- **3 Sep** Removing or saving a prefab instance finds every member, cut brushes included, and warns about a missing one instead of doing part of the job. (issue [#66](https://github.com/saworbit/hammerforge/issues/66), commit [6e0b740](https://github.com/saworbit/hammerforge/commit/6e0b7402c4cd24d1bc0c873e081444306d5b6447))
- **2 Sep** Playtest exports are complete and playable, with the player at the spawn, all nested bake and I/O nodes, and entities and sun kept in place. (PR [#57](https://github.com/saworbit/hammerforge/pull/57))
- **2 Sep** MultiMesh bakes keep each instance where it was placed. (PR [#57](https://github.com/saworbit/hammerforge/pull/57))
- **2 Sep** Brush entities take part in I/O everywhere: bake, exported scenes, connection lists, dangling-link cleanup and target renames. (PR [#57](https://github.com/saworbit/hammerforge/pull/57))
- **2 Sep** A downward Polygon height stays positive, and Path auto-trim can use material palette slot 0. (PR [#57](https://github.com/saworbit/hammerforge/pull/57))

#### Behind the scenes

- **3 Sep** Viewport input, numeric entry, paint input, selection, edit actions, drops and overlays move out of `plugin.gd` into focused modules. (issue [#41](https://github.com/saworbit/hammerforge/issues/41), PR [#82](https://github.com/saworbit/hammerforge/pull/82))
- **3 Sep** Dock file, visgroup and settings handling moves out of `dock.gd` into three focused files. (issue [#22](https://github.com/saworbit/hammerforge/issues/22), PR [#72](https://github.com/saworbit/hammerforge/pull/72))
- **3 Sep** Tests cover HFLog warning capture, suppression and buffer lifetime. (PR [#64](https://github.com/saworbit/hammerforge/pull/64))
- **3 Sep** A `tools/benchmark_bake_atlas.gd` benchmark measures the atlas gutter fill and atlas builds with and without PBR maps. (PR [#64](https://github.com/saworbit/hammerforge/pull/64))
- **3 Sep** Tests cover PBR atlas packing: per-map packing, flat tiles, carried settings, every skip reason and the shared layout. (PR [#64](https://github.com/saworbit/hammerforge/pull/64))
- **3 Sep** A `tools/benchmark_paint_hot_paths.gd` benchmark reports paint costs so the numbers in a paint speed-up PR are reproducible. (PR [#63](https://github.com/saworbit/hammerforge/pull/63))
- **3 Sep** Tests cover surface painting, face paint compositing and the terrain brush, none of which had direct tests before. (PR [#63](https://github.com/saworbit/hammerforge/pull/63))
- **3 Sep** The repo gains `SECURITY.md`, a code of conduct, issue forms, a pull request template and Dependabot for GitHub Actions. (PR [#62](https://github.com/saworbit/hammerforge/pull/62))
- **2 Sep** The entity container check in HFValidation reads LevelRoot's real `entities_node` property. (PR [#57](https://github.com/saworbit/hammerforge/pull/57))
- **2 Sep** README, guides, spec and checklists agree on tab names, snap modes, playtest export, architecture and CI totals. (PR [#57](https://github.com/saworbit/hammerforge/pull/57))

### Week of 24 Aug 2026

#### Added

- **28 Aug** Snap to perpendicular (P in the dock) drops the cursor onto the nearest point of a brush edge, square to it. (commit [61fed6f](https://github.com/saworbit/hammerforge/commit/61fed6f713161464565c314ae072aafe64f08030))
- **28 Aug** The playtest player has a reticle and an Esc pause and controls overlay, and uses 9.8 gravity as a fallback. (commit [f9030d6](https://github.com/saworbit/hammerforge/commit/f9030d62d08f212d8de6f2e93598c696077098bb))

#### Changed

- **28 Aug** Test Level wires entity I/O by default, so connections fire without an Inspector toggle. (commit [f9030d6](https://github.com/saworbit/hammerforge/commit/f9030d62d08f212d8de6f2e93598c696077098bb))
- **28 Aug** The wireframe bake preview compiles its shader once instead of on every bake. (commit [f9030d6](https://github.com/saworbit/hammerforge/commit/f9030d62d08f212d8de6f2e93598c696077098bb))
- **28 Aug** The History section skips thumbnail captures while hidden and adds new rows instead of rebuilding the list. (commit [96321f4](https://github.com/saworbit/hammerforge/commit/96321f42f3ad2186de4605b991aabcab046597c4))
- **28 Aug** With `bake_use_thread_pool` on, merged-mesh bakes group surfaces on a worker thread. (commit [61fed6f](https://github.com/saworbit/hammerforge/commit/61fed6f713161464565c314ae072aafe64f08030))
- **28 Aug** `.hflevel` saves encode and compress off the main thread, and skip the disk write when nothing has changed. (commit [839a64b](https://github.com/saworbit/hammerforge/commit/839a64b139fab3b2feee1d70dd53c2941c9d901f))

#### Fixed

- **28 Aug** Tied `func_detail` and trigger brushes bake again, as detail meshes with collision and trigger volumes that keep their I/O. (commit [838dd1d](https://github.com/saworbit/hammerforge/commit/838dd1d8d0f8e0b1090955fc7fbeea88b0bd7136))
- **28 Aug** `.map` brush entities round-trip: `func_detail`, `func_wall` and triggers export as their own entities and import with their class set. (commit [96321f4](https://github.com/saworbit/hammerforge/commit/96321f42f3ad2186de4605b991aabcab046597c4))
- **28 Aug** `.map` export keeps point entity keys such as angle and targetname, not just classname and origin. (commit [f9030d6](https://github.com/saworbit/hammerforge/commit/f9030d62d08f212d8de6f2e93598c696077098bb))
- **28 Aug** `.hflevel` saves write to a side file and swap it in, so the old level is no longer truncated before the new one is written. (commit [f9030d6](https://github.com/saworbit/hammerforge/commit/f9030d62d08f212d8de6f2e93598c696077098bb))
- **28 Aug** The `hflevel_compress` setting really compresses `.hflevel` files; uncompressed files still load. (commit [f9030d6](https://github.com/saworbit/hammerforge/commit/f9030d62d08f212d8de6f2e93598c696077098bb))
- **28 Aug** Displacements shade smoothly with averaged vertex normals instead of flat per-triangle shading. (commit [96321f4](https://github.com/saworbit/hammerforge/commit/96321f42f3ad2186de4605b991aabcab046597c4))
- **28 Aug** Prefab capture takes its origin from the members' combined visible bounds, so one oversized brush cannot skew placement. (commit [96321f4](https://github.com/saworbit/hammerforge/commit/96321f42f3ad2186de4605b991aabcab046597c4))

#### Behind the scenes

- **28 Aug** The I/O runtime finds its dispatchers through a group instead of walking the scene tree. (commit [f9030d6](https://github.com/saworbit/hammerforge/commit/f9030d62d08f212d8de6f2e93598c696077098bb))

### Week of 17 Aug 2026

#### Added

- **22 Aug** Snap to edge (E or Edges in the dock) snaps to the edge midpoints of existing brushes' bounding boxes. (PR [#8](https://github.com/saworbit/hammerforge/pull/8))
- **22 Aug** A project's `res://hammerforge_entities.json` adds to the plugin's entity list, its classes winning on a name clash. (commit [915cb94](https://github.com/saworbit/hammerforge/commit/915cb949e2c875ed95992735fe858fbf6979ddda))

#### Changed

- **22 Aug** Overlapping subtract brushes preview the real CSG cut after a short two-frame bake, with box wireframes shown in the meantime. (commit [9295d72](https://github.com/saworbit/hammerforge/commit/9295d725d8173a3922f2c99ae09f233227f3fb23))
- **22 Aug** Heightmap conversion reads additive brushes' mesh bounds, displacement height included, and skips subtract brushes. (commit [9295d72](https://github.com/saworbit/hammerforge/commit/9295d725d8173a3922f2c99ae09f233227f3fb23))
- **22 Aug** The default editor sticks to the core loop; radial menu, coach marks and operation replay move behind Test → Settings → Power-user overlays. (commit [9295d72](https://github.com/saworbit/hammerforge/commit/9295d725d8173a3922f2c99ae09f233227f3fb23))

#### Fixed

- **22 Aug** The subtract preview includes draft brushes, using their mesh bounds, instead of skipping them. (commit [915cb94](https://github.com/saworbit/hammerforge/commit/915cb949e2c875ed95992735fe858fbf6979ddda))
- **22 Aug** Rotated and complex brushes go through `.map` import and export with their real face planes instead of becoming boxes or cylinders. (commit [915cb94](https://github.com/saworbit/hammerforge/commit/915cb949e2c875ed95992735fe858fbf6979ddda))

#### Behind the scenes

- **22 Aug** Test-tab bake and play handlers move from `dock.gd` into `dock_manage_handler.gd`. (PR [#20](https://github.com/saworbit/hammerforge/pull/20))
- **22 Aug** Objects-tab entity handlers move from `dock.gd` into `dock_entity_handler.gd`. (PR [#19](https://github.com/saworbit/hammerforge/pull/19))
- **22 Aug** Build-tab brush handlers move from `dock.gd` into `dock_brush_handler.gd`. (PR [#18](https://github.com/saworbit/hammerforge/pull/18))
- **22 Aug** BrushManager only mirrors the brush list while HFBrushSystem owns brush lifetime; multi-brush edits batch their signals. (PR [#8](https://github.com/saworbit/hammerforge/pull/8))
- **22 Aug** Paint-tab handlers move from `dock.gd` into `dock_paint_handler.gd`. (commit [7862584](https://github.com/saworbit/hammerforge/commit/7862584fcee4fa5ee6d2133ec860887adc042dc1))
- **22 Aug** HUD and context toolbar state move from `plugin.gd` into `plugin_hud.gd`. (commit [c87399b](https://github.com/saworbit/hammerforge/commit/c87399b32f30565049f6d0b2318d211fa5215ce7))
- **22 Aug** Vertex and edge input moves from `plugin.gd` into `plugin_vertex_input.gd`. (commit [34c8f70](https://github.com/saworbit/hammerforge/commit/34c8f70105a2116e2ba5694064106630deb1e2ee))
- **22 Aug** Viewport keymap handling moves from `plugin.gd` into `plugin_input_router.gd`. (commit [5d5413f](https://github.com/saworbit/hammerforge/commit/5d5413fc312d913f1b06a8a611d208f3b37c7ea2))
- **22 Aug** Context toolbar, hotkey palette, viewport menu and radial menu share one command dispatcher instead of three copied blocks. (commit [36391f1](https://github.com/saworbit/hammerforge/commit/36391f171d722c86eec30565e1442abe3e84991c))
- **22 Aug** The vendored Godot MCP Native moves to 1.0.8; its HTTP server still binds to 127.0.0.1 unless remote access is on. (commit [16f6bce](https://github.com/saworbit/hammerforge/commit/16f6bceff056e92956e47a8dac456f3e6df24ee2))
- **22 Aug** The MCP script scanner reads compiled scripts, so it no longer floods the editor Output with false parse errors. (commit [16f6bce](https://github.com/saworbit/hammerforge/commit/16f6bceff056e92956e47a8dac456f3e6df24ee2))

### Week of 20 Jul 2026

#### Changed

- **21 Jul** Measure sets its snap reference with Ctrl+Click instead of right-click, and quick-property popups close without eating camera navigation. (commit [9778a12](https://github.com/saworbit/hammerforge/commit/9778a122e06f2cbb10469532378f4228609aabb7))

#### Fixed

- **21 Jul** A gizmo or resize-handle drag owns mouse and keyboard until release, so no marquee or nudge fires mid-drag; mixed selections edit all or nothing. (commit [abff7cb](https://github.com/saworbit/hammerforge/commit/abff7cb111fede0053de1abdadef8908d5092cf8))
- **21 Jul** Spheres, cylinders, cones and capsules draw where dragged without drifting or floating, and entities with broken previews stay clickable. (commit [abff7cb](https://github.com/saworbit/hammerforge/commit/abff7cb111fede0053de1abdadef8908d5092cf8))
- **21 Jul** Bake Changed catches every edit, Inspector and undo/redo included; nudges and material, UV and paint changes could be silently skipped. (commit [abff7cb](https://github.com/saworbit/hammerforge/commit/abff7cb111fede0053de1abdadef8908d5092cf8))
- **21 Jul** Rapid drawing and resizing leave no stray green wireframe copies, and additive brushes lose their always-on triangle wireframe. (commit [abff7cb](https://github.com/saworbit/hammerforge/commit/abff7cb111fede0053de1abdadef8908d5092cf8))
- **21 Jul** Material and brush entity tie/untie changes show at once, and unmaterialed polygon, path and custom brushes show their real shape, not a box. (commit [abff7cb](https://github.com/saworbit/hammerforge/commit/abff7cb111fede0053de1abdadef8908d5092cf8))
- **21 Jul** Repeated bakes replace the baked geometry instead of piling up saved `@Node3D@` containers, and a reopened scene keeps its bake. (commit [abff7cb](https://github.com/saworbit/hammerforge/commit/abff7cb111fede0053de1abdadef8908d5092cf8))
- **21 Jul** Right-mouse camera look and WASD flight work whatever is selected; HammerForge keeps out of the whole session. (issue [#5](https://github.com/saworbit/hammerforge/issues/5), commit [abff7cb](https://github.com/saworbit/hammerforge/commit/abff7cb111fede0053de1abdadef8908d5092cf8))
- **21 Jul** Selection follows Godot's exactly, so clearing it leaves no hidden brush selected; Object Select clicks and marquees use Godot's own picking. (commit [abff7cb](https://github.com/saworbit/hammerforge/commit/abff7cb111fede0053de1abdadef8908d5092cf8))
- **21 Jul** Face Select turns Paint off and hides object gizmos; mixed Godot and HammerForge selections are blocked before a partial edit can corrupt undo. (commit [abff7cb](https://github.com/saworbit/hammerforge/commit/abff7cb111fede0053de1abdadef8908d5092cf8))
- **21 Jul** Resize handles snap in world units and keep the opposite face fixed under rotated or scaled parents; spheres stay round. (commit [abff7cb](https://github.com/saworbit/hammerforge/commit/abff7cb111fede0053de1abdadef8908d5092cf8))
- **21 Jul** Clicking, hovering and dropping hit a brush's visible faces, not its bounding box; the empty corners around a wedge or cone used to count. (commit [abff7cb](https://github.com/saworbit/hammerforge/commit/abff7cb111fede0053de1abdadef8908d5092cf8))

#### Behind the scenes

- **21 Jul** The repo ignores `.codex/` client state, and the Godot MCP setup is documented as local contributor configuration. (commit [9778a12](https://github.com/saworbit/hammerforge/commit/9778a122e06f2cbb10469532378f4228609aabb7))

### Week of 4 May 2026

#### Behind the scenes

- **7 May** Shared helpers for UI building, validation, theme, undo navigation, tooltips and dialogs come out of the dock and plugin, with 75-plus tests. (commit [e10d2ec](https://github.com/saworbit/hammerforge/commit/e10d2ec7cb015b921dffe7dc9719d6e36ddc2f63))

### Week of 13 Apr 2026

#### Added

- **13 Apr** With subtract brushes pending, the Draw toolbar shows Apply, Commit and Clear buttons and a pending count, so you can stay in the viewport. (commit [a3dac42](https://github.com/saworbit/hammerforge/commit/a3dac4243cd454e73c546b5a8116b8539299037c))
- **13 Apr** A Bake▷ toggle on the brush toolbar bakes a quick wireframe preview of the final mesh; toggling it off bakes at full quality. (commit [a3dac42](https://github.com/saworbit/hammerforge/commit/a3dac4243cd454e73c546b5a8116b8539299037c))
- **13 Apr** One click in the Manage tab starts a new level with a floor, a sun and a player spawn, as a single undoable step. (commit [8ae8364](https://github.com/saworbit/hammerforge/commit/8ae8364a2f1835e1766fb834ff3a453e92b0a00a))
- **13 Apr** E and Shift+E extrude up and down, A and Shift+A select and deselect all, and the context toolbar labels its tool groups. (commit [1b9c958](https://github.com/saworbit/hammerforge/commit/1b9c958ead854a071ba084dc8d6d41467cb5b612))

#### Fixed

- **13 Apr** Playtest lighting matches the editor: the level's sun is carried over, and the fallback sun no longer faces the opposite way. (commit [8ae8364](https://github.com/saworbit/hammerforge/commit/8ae8364a2f1835e1766fb834ff3a453e92b0a00a))

#### Behind the scenes

- **13 Apr** The dock emits `bake_state_changed`, so the context toolbar disables and re-enables its buttons the moment a bake starts or ends. (commit [a3dac42](https://github.com/saworbit/hammerforge/commit/a3dac4243cd454e73c546b5a8116b8539299037c))
- **13 Apr** Runtime warnings go through HFLog, so tests can capture and silence the warnings they expect. (commit [8ae8364](https://github.com/saworbit/hammerforge/commit/8ae8364a2f1835e1766fb834ff3a453e92b0a00a))

### Week of 6 Apr 2026

#### Added

- **12 Apr** Carve, Clip and Hollow show a wireframe preview and ask before committing, and deleting three or more brushes asks first. (commit [9e76616](https://github.com/saworbit/hammerforge/commit/9e766161da0a583b7df35efc5e62ee174c0756e6))
- **12 Apr** Wireframes are coded by type (green add, red subtract, blue brush entity), the viewport shows grid size, and [ and ] halve or double it. (commit [88b3d61](https://github.com/saworbit/hammerforge/commit/88b3d61e139b361a3ddaee7a784dc8036aa1a515))
- **11 Apr** Space opens a viewport context menu, backtick a radial tool menu, and double-tapping G, B or R opens a quick property popup. (commit [647592d](https://github.com/saworbit/hammerforge/commit/647592d1a8c6ba84a2d163dc670e663c905c6123))
- **10 Apr** Bake can generate occluders from large flat surfaces for occlusion culling, set by Generate Occluders and Min Area in the Manage tab. (commit [0664c9b](https://github.com/saworbit/hammerforge/commit/0664c9bc88260cbea917d13eb586ddc19712b830))
- **10 Apr** Entity I/O connections become live Godot signals at bake and export, so exported scenes fire I/O without hand wiring. (commit [548dcdd](https://github.com/saworbit/hammerforge/commit/548dcdd8e58113e3a1757742493116b3527fa73a))
- **10 Apr** `bake_collision_mode` adds per-brush convex hulls or per-visgroup bodies beside the single trimesh, for better physics and bot navigation. (commit [b34af59](https://github.com/saworbit/hammerforge/commit/b34af5986dbf5b80ebaeda1bef9ee6065594f738))

#### Changed

- **12 Apr** Entity I/O and I/O Wiring in the Entities tab appear only with an entity selected, and I/O Wiring starts collapsed. (commit [021f208](https://github.com/saworbit/hammerforge/commit/021f2088acbad7efaa9724d43037bcc7572fb610))

#### Behind the scenes

- **12 Apr** Three test files stop leaking resources, so the full suite shuts down cleanly. (commit [88b3d61](https://github.com/saworbit/hammerforge/commit/88b3d61e139b361a3ddaee7a784dc8036aa1a515))

## [0.2.0] - 2026-04-09

**Highlights**

- The Hammer toolset arrives: Hollow, Clip, Carve, Merge, Bevel, Inset, displacements, entity I/O, visgroups, groups and cordon.
- Prefabs with variants and linked instances, a texture browser with 150 prototype textures, and per-face UV tools.
- Floor paint grows heightmaps, terrain blending, region streaming and automatic ramps and stairs between layers.
- The dock goes from eight tabs to four, with a context toolbar, a command palette and rebindable shortcuts.
- Valve 220 `.map` export, bake issue checks, bakes of only what changed, and material atlasing.

The long write-ups, as first written: [changelog/0.2.0.md](changelog/0.2.0.md)

### Week of 6 Apr 2026

#### Added

- **9 Apr** `.map` import welds vertices closer than 0.01 units together, closing micro-gaps left by older map editors. (commit [e9430a1](https://github.com/saworbit/hammerforge/commit/e9430a166fe68c98a9862c9f6a10c306693f8284))
- **9 Apr** Bake issue checks flag non-planar faces, where a corner of a face with four or more corners strays over 0.01 units off its plane. (commit [e9430a1](https://github.com/saworbit/hammerforge/commit/e9430a166fe68c98a9862c9f6a10c306693f8284))
- **9 Apr** Bake issue checks flag micro-gaps: vertices on different brushes that almost meet and would tear seams after bake. (commit [e9430a1](https://github.com/saworbit/hammerforge/commit/e9430a166fe68c98a9862c9f6a10c306693f8284))
- **8 Apr** Auto Connectors build ramps or stairs between paint layers at different heights during bake, set in the Manage tab's Bake section. (commit [b8cf0df](https://github.com/saworbit/hammerforge/commit/b8cf0dfabeb75fc223144d0c8a7b12cce368aab0))
- **7 Apr** Merge (Ctrl+Shift+M) combines two or more selected brushes into one, keeping rotation, scale and every face's material. (commit [10cd2d7](https://github.com/saworbit/hammerforge/commit/10cd2d7da89a1dc6407491bc1abf68cb3023ddf2))
- **6 Apr** Material Atlas (Manage tab, Bake) packs face textures into one atlas to cut draw calls; tiling faces keep their own material. (commit [a0e148d](https://github.com/saworbit/hammerforge/commit/a0e148d8ea6dcf7e884e53d3a08e5f191a38615c))
- **6 Apr** Source Engine-style displacements on quad faces: raise, lower, smooth, add noise and sew edges from the Brush tab, all undoable. (commit [dd2a650](https://github.com/saworbit/hammerforge/commit/dd2a650744fe8148bcc3dc2580448f8b2070d0d3))
- **6 Apr** Bevel replaces a selected edge with 1 to 16 rounded segments; pick the edge in vertex mode (V) and set segments and radius in the dock. (commit [dd2a650](https://github.com/saworbit/hammerforge/commit/dd2a650744fe8148bcc3dc2580448f8b2070d0d3))
- **6 Apr** Inset shrinks a face inward by a set distance and joins it with side quads, optionally extruding it by a height. (commit [dd2a650](https://github.com/saworbit/hammerforge/commit/dd2a650744fe8148bcc3dc2580448f8b2070d0d3))

#### Changed

- **9 Apr** Full bakes with Face Materials on no longer freeze the editor; they work through brushes in batches and report progress. (commit [4f9c47e](https://github.com/saworbit/hammerforge/commit/4f9c47ea9eb0f5f0e3c962ac2bc225ae0c1e01be))

#### Fixed

- **8 Apr** Drag, extrude and subtract previews no longer leak nodes during rapid undo and redo. (commit [1ab59e5](https://github.com/saworbit/hammerforge/commit/1ab59e5de2b1a4c3bd2cf11a123c3084a55eff35))
- **8 Apr** Navmesh bakes set collider-only parsing on Godot 4.6; every bake used to log an error and silently skip it. (commit [b8cf0df](https://github.com/saworbit/hammerforge/commit/b8cf0dfabeb75fc223144d0c8a7b12cce368aab0))
- **7 Apr** Dialogs and timers in the dock, spawn system and prefab library no longer throw freed-object errors after a plugin reload. (commit [10cd2d7](https://github.com/saworbit/hammerforge/commit/10cd2d7da89a1dc6407491bc1abf68cb3023ddf2))
- **6 Apr** Box, polygon and path brushes show textures on the outside; they used to render inside out, and old saves migrate on load. (commit [7a9de07](https://github.com/saworbit/hammerforge/commit/7a9de0729fa2aa213e6b8a03a5e5b672e7c58d5c))

#### Behind the scenes

- **9 Apr** Validation gains a vertex weld auto-fix, `weld_brush_vertices()`, that snaps a brush's nearly coincident vertices to their average. (commit [e9430a1](https://github.com/saworbit/hammerforge/commit/e9430a166fe68c98a9862c9f6a10c306693f8284))
- **9 Apr** Validation gains a planarity auto-fix, `fix_non_planar_faces()`, that projects drifting vertices back onto each face's plane. (commit [e9430a1](https://github.com/saworbit/hammerforge/commit/e9430a166fe68c98a9862c9f6a10c306693f8284))
- **9 Apr** Validation exposes `weld_tolerance` and `planarity_tolerance`; the open and non-manifold edge checks keep their own fixed precision. (commit [e9430a1](https://github.com/saworbit/hammerforge/commit/e9430a166fe68c98a9862c9f6a10c306693f8284))
- **6 Apr** LevelRoot gains delegates for the displacement, bevel and inset operations so each one can go through undo. (commit [dd2a650](https://github.com/saworbit/hammerforge/commit/dd2a650744fe8148bcc3dc2580448f8b2070d0d3))
- **6 Apr** A shared dock helper records undo and history only when a displacement or bevel action succeeds, so failures leave no empty step. (commit [dd2a650](https://github.com/saworbit/hammerforge/commit/dd2a650744fe8148bcc3dc2580448f8b2070d0d3))
- **6 Apr** 55 new tests cover displacements and bevels. (commit [dd2a650](https://github.com/saworbit/hammerforge/commit/dd2a650744fe8148bcc3dc2580448f8b2070d0d3))
- **6 Apr** 29 new tests cover merged geometry, chunked previews, UV undo merging, baked materials and winding migration. (commit [7a9de07](https://github.com/saworbit/hammerforge/commit/7a9de0729fa2aa213e6b8a03a5e5b672e7c58d5c))

### Week of 30 Mar 2026

#### Added

- **5 Apr** Convex (vertex edit toolbar and command palette) rebuilds a brush as its convex hull, keeping each face's UVs and material. (commit [fed33ed](https://github.com/saworbit/hammerforge/commit/fed33ed17a220f646e07108c9fd8d619da4a491f))
- **5 Apr** A Chunk Size spinbox (0 to 256, default 32) in the Manage tab's Bake section sets `bake_chunk_size` from the dock. (commit [fed33ed](https://github.com/saworbit/hammerforge/commit/fed33ed17a220f646e07108c9fd8d619da4a491f))
- **5 Apr** A Bake Visible Only checkbox in the Manage tab's Bake section skips hidden brushes during bake. (commit [fed33ed](https://github.com/saworbit/hammerforge/commit/fed33ed17a220f646e07108c9fd8d619da4a491f))
- **5 Apr** Use MultiMesh (Manage tab, Bake) swaps repeated identical baked meshes for MultiMesh instances, keeping their materials. (commit [fed33ed](https://github.com/saworbit/hammerforge/commit/fed33ed17a220f646e07108c9fd8d619da4a491f))
- **5 Apr** Bake issue checks warn about open edges and about non-manifold edges shared by three or more faces. (commit [fed33ed](https://github.com/saworbit/hammerforge/commit/fed33ed17a220f646e07108c9fd8d619da4a491f))
- **5 Apr** Per-face UV controls in the Paint tab: projection (Planar X/Y/Z, Box UV, Cylindrical), scale, offset, rotation and Re-project. (commit [fed33ed](https://github.com/saworbit/hammerforge/commit/fed33ed17a220f646e07108c9fd8d619da4a491f))
- **5 Apr** An optional Unwrap UV0 bake toggle projects planar UVs along each vertex's dominant normal axis. (commit [fed33ed](https://github.com/saworbit/hammerforge/commit/fed33ed17a220f646e07108c9fd8d619da4a491f))
- **5 Apr** Subtract brushes draw a red-orange wireframe overlay so they stay easy to see. (commit [fed33ed](https://github.com/saworbit/hammerforge/commit/fed33ed17a220f646e07108c9fd8d619da4a491f))
- **5 Apr** Stretch and Tile justify modes: Stretch fills the face on both axes, Tile keeps the aspect ratio and tiles the longer axis. (commit [b574fd6](https://github.com/saworbit/hammerforge/commit/b574fd6344660ca3902260d8b83f81920dd2671a))
- **5 Apr** Custom panels follow Godot's dark or light theme, and the Manage tab gains an undo history browser with viewport thumbnails. (commit [1d904c7](https://github.com/saworbit/hammerforge/commit/1d904c78258fa5c2991d1baf1c73961ecef89ba8))
- **4 Apr** Convert Selection to Heightmap turns brushes into a sculptable heightmap layer, and a Foliage & Scatter brush places meshes. (PR [#2](https://github.com/saworbit/hammerforge/pull/2))
- **3 Apr** Coach marks guide first use of ten advanced tools, and an operation replay timeline (Ctrl+Shift+T) steps through recent history. (PR [#1](https://github.com/saworbit/hammerforge/pull/1))
- **3 Apr** I/O connections draw as curved, color-coded arrows, and the Entities tab gains a wiring panel with reusable connection presets. (PR [#1](https://github.com/saworbit/hammerforge/pull/1))
- **3 Apr** Bake Selected and Bake Changed bake only part of a level, and Quick Play gains Play from Camera and Play Selected Area. (commit [34eb040](https://github.com/saworbit/hammerforge/commit/34eb0403f4d58f7572609daee6da1816dfae35fc))
- **1 Apr** Prefabs can hold variants, such as door styles; cycle a placed instance with Ctrl+Shift+V or the Var▶ toolbar button. (commit [8d3f2f6](https://github.com/saworbit/hammerforge/commit/8d3f2f6cad48850d34cb0431d04d1745d7d26e96))
- **1 Apr** Save Linked keeps prefab instances tied to their `.hfprefab` file: Push edits back to it, or Pull it into every linked instance. (commit [8d3f2f6](https://github.com/saworbit/hammerforge/commit/8d3f2f6cad48850d34cb0431d04d1745d7d26e96))
- **1 Apr** The prefab library is searchable, filters by tag, shows variant counts and has a right-click menu. (commit [8d3f2f6](https://github.com/saworbit/hammerforge/commit/8d3f2f6cad48850d34cb0431d04d1745d7d26e96))
- **1 Apr** Ctrl+Shift+P or the Pfb toolbar button saves the selection as a prefab with an auto-generated name. (commit [8d3f2f6](https://github.com/saworbit/hammerforge/commit/8d3f2f6cad48850d34cb0431d04d1745d7d26e96))
- **1 Apr** Hovering a prefab instance draws a cyan box around it, with orange markers on nodes that override the prefab. (commit [8d3f2f6](https://github.com/saworbit/hammerforge/commit/8d3f2f6cad48850d34cb0431d04d1745d7d26e96))
- **31 Mar** Drag a marquee to select brushes, entities or faces, and open selection filters (Shift+F) to pick walls, floors, materials and more. (commit [dae170d](https://github.com/saworbit/hammerforge/commit/dae170d414a5cd4b8d1c9ca597946797f6f2a00f))
- **30 Mar** A floating context toolbar shows actions for the current selection or tool, and a command palette (Shift+? or F1) searches every action. (commit [098c8af](https://github.com/saworbit/hammerforge/commit/098c8af32a6308dcbf4e55775c2b16535c8eae01))

#### Changed

- **5 Apr** The Bake button bakes only the changed brushes when it can, skipping full re-bakes during iterative editing. (commit [fed33ed](https://github.com/saworbit/hammerforge/commit/fed33ed17a220f646e07108c9fd8d619da4a491f))
- **5 Apr** Baked meshes keep per-face materials, with one surface per material in a single mesh. (commit [fed33ed](https://github.com/saworbit/hammerforge/commit/fed33ed17a220f646e07108c9fd8d619da4a491f))
- **30 Mar** Material assignment no longer requires a face selection; with only brushes selected, double-click or Assign covers whole brushes. (commit [098c8af](https://github.com/saworbit/hammerforge/commit/098c8af32a6308dcbf4e55775c2b16535c8eae01))

#### Fixed

- **5 Apr** Merged bake geometry keeps its triangles intact; indexed surfaces used to come out corrupted or be dropped. (commit [fed33ed](https://github.com/saworbit/hammerforge/commit/fed33ed17a220f646e07108c9fd8d619da4a491f))
- **5 Apr** Rebuilding a brush from its convex hull keeps every face; corners shared by several faces used to drop faces and leave holes. (commit [fed33ed](https://github.com/saworbit/hammerforge/commit/fed33ed17a220f646e07108c9fd8d619da4a491f))
- **5 Apr** Wireframe and Proxy bake previews reach meshes inside chunked bakes; nested chunk meshes used to be skipped. (commit [fed33ed](https://github.com/saworbit/hammerforge/commit/fed33ed17a220f646e07108c9fd8d619da4a491f))
- **5 Apr** UV spinbox edits are undoable, and a spinbox drag merges into a single undo step. (commit [fed33ed](https://github.com/saworbit/hammerforge/commit/fed33ed17a220f646e07108c9fd8d619da4a491f))
- **5 Apr** Dragging a UV spinbox adds one history entry instead of flooding the history list with duplicates. (commit [fed33ed](https://github.com/saworbit/hammerforge/commit/fed33ed17a220f646e07108c9fd8d619da4a491f))
- **5 Apr** The Unwrap UV0 bake toggle is saved in `.hflevel`; it used to reset silently. (commit [fed33ed](https://github.com/saworbit/hammerforge/commit/fed33ed17a220f646e07108c9fd8d619da4a491f))
- **5 Apr** Rotated textures with an offset no longer drift; rotation applies first, matching Valve 220, and older saves are migrated. (commit [b574fd6](https://github.com/saworbit/hammerforge/commit/b574fd6344660ca3902260d8b83f81920dd2671a))
- **5 Apr** Carved pieces keep the original brush's UV scale, offset, rotation and material, so textures stay aligned; they used to reset. (commit [b574fd6](https://github.com/saworbit/hammerforge/commit/b574fd6344660ca3902260d8b83f81920dd2671a))
- **5 Apr** Tile justify fills the shorter axis and tiles the longer one; it used to letterbox by fitting the longer axis. (commit [b574fd6](https://github.com/saworbit/hammerforge/commit/b574fd6344660ca3902260d8b83f81920dd2671a))
- **3 Apr** The plugin script no longer fails to parse over a duplicate variable in the Highlight Connected toolbar action. (PR [#1](https://github.com/saworbit/hammerforge/pull/1))
- **3 Apr** The tutorial's two-second close timer no longer calls into a freed dock if the dock goes away first. (PR [#1](https://github.com/saworbit/hammerforge/pull/1))
- **3 Apr** Autosave and reload timer nodes are freed when the level leaves the scene instead of leaking. (PR [#1](https://github.com/saworbit/hammerforge/pull/1))
- **3 Apr** Decal, measure, path, polygon and prefab tools no longer crash removing a node that has no parent. (PR [#1](https://github.com/saworbit/hammerforge/pull/1))
- **3 Apr** Restoring a state removes old brushes and entities at once; they used to linger in the tree beside the new ones. (PR [#1](https://github.com/saworbit/hammerforge/pull/1))
- **3 Apr** Merging vertices when none of the picked indices is valid stops quietly instead of dividing by zero. (PR [#1](https://github.com/saworbit/hammerforge/pull/1))
- **3 Apr** Hovering edges in vertex mode checks the edge first, so a malformed pick no longer reads out of bounds. (PR [#1](https://github.com/saworbit/hammerforge/pull/1))
- **3 Apr** Extrude no longer leaks its preview brush when the level has no brush container to hold it. (PR [#1](https://github.com/saworbit/hammerforge/pull/1))
- **3 Apr** Axis lock constrains brush drags; its position clamping used to be silently ignored. (PR [#1](https://github.com/saworbit/hammerforge/pull/1))
- **1 Apr** Toolbar, palette and dock actions fire once after a plugin reload; ten signals were never disconnected and stacked up. (commit [50a0993](https://github.com/saworbit/hammerforge/commit/50a09934e1623a5026f7babfe6c9be7d0f11d812))
- **1 Apr** Autosave and reload timers stop and disconnect when the level leaves the scene; turning autosave off used to leave a signal connected. (commit [50a0993](https://github.com/saworbit/hammerforge/commit/50a09934e1623a5026f7babfe6c9be7d0f11d812))
- **1 Apr** Extrude cancels cleanly if its brush is deleted mid-extrude, for example by undo, instead of crashing. (commit [50a0993](https://github.com/saworbit/hammerforge/commit/50a09934e1623a5026f7babfe6c9be7d0f11d812))
- **1 Apr** Starting a drag, paint, extrude or vertex edit while another tool is active resets the first one and clears its preview. (commit [50a0993](https://github.com/saworbit/hammerforge/commit/50a09934e1623a5026f7babfe6c9be7d0f11d812))
- **1 Apr** Hiding the prefab overlay no longer crashes when its parent was freed during plugin unload. (commit [50a0993](https://github.com/saworbit/hammerforge/commit/50a09934e1623a5026f7babfe6c9be7d0f11d812))
- **1 Apr** Splitting an edge checks the edge first, so malformed input no longer reads out of bounds. (commit [50a0993](https://github.com/saworbit/hammerforge/commit/50a09934e1623a5026f7babfe6c9be7d0f11d812))
- **1 Apr** Prefab code no longer fails to parse on Godot 4.6, and prefab instances keep their overlay and toolbar badge after undo. (commit [8d3f2f6](https://github.com/saworbit/hammerforge/commit/8d3f2f6cad48850d34cb0431d04d1745d7d26e96))
- **31 Mar** Dock Undo and Redo buttons act on the scene's history instead of doing nothing; heightmap import and its dialogs work on Godot 4.6. (commit [dae170d](https://github.com/saworbit/hammerforge/commit/dae170d414a5cd4b8d1c9ca597946797f6f2a00f))
- **31 Mar** The selection filter popup opens; it was never added to the editor, so it failed silently. (commit [dae170d](https://github.com/saworbit/hammerforge/commit/dae170d414a5cd4b8d1c9ca597946797f6f2a00f))
- **31 Mar** Brush-only selection filters clear the face selection, so the toolbar and material actions stop targeting old faces. (commit [dae170d](https://github.com/saworbit/hammerforge/commit/dae170d414a5cd4b8d1c9ca597946797f6f2a00f))
- **31 Mar** Apply Last Texture and the toolbar material apply cover every selected brush, not just the first. (commit [dae170d](https://github.com/saworbit/hammerforge/commit/dae170d414a5cd4b8d1c9ca597946797f6f2a00f))
- **31 Mar** Walls, Floors, Ceilings and Select Similar Faces judge faces in world space, so rotated brushes sort correctly. (commit [dae170d](https://github.com/saworbit/hammerforge/commit/dae170d414a5cd4b8d1c9ca597946797f6f2a00f))
- **30 Mar** Texture reimport no longer clears brush selection; loading prototype textures in the material browser used to drop it. (commit [098c8af](https://github.com/saworbit/hammerforge/commit/098c8af32a6308dcbf4e55775c2b16535c8eae01))

#### Behind the scenes

- **5 Apr** The undo helper's path for more than five arguments collates repeated calls; it compared against empty state and never merged. (commit [fed33ed](https://github.com/saworbit/hammerforge/commit/fed33ed17a220f646e07108c9fd8d619da4a491f))
- **5 Apr** The undo helper handles methods with up to five arguments instead of three, so face UV edits can be undone. (commit [fed33ed](https://github.com/saworbit/hammerforge/commit/fed33ed17a220f646e07108c9fd8d619da4a491f))
- **5 Apr** Faces gain a texture-lock helper for rotation, ready to wire in once brushes can rotate. (commit [b574fd6](https://github.com/saworbit/hammerforge/commit/b574fd6344660ca3902260d8b83f81920dd2671a))
- **3 Apr** Leftover debug `and true` conditions are removed from four surface paint and UV dock handlers. (PR [#1](https://github.com/saworbit/hammerforge/pull/1))
- **1 Apr** A prefab subsystem tracks instances, variants, overrides and linked updates, with undo through state capture. (commit [8d3f2f6](https://github.com/saworbit/hammerforge/commit/8d3f2f6cad48850d34cb0431d04d1745d7d26e96))
- **1 Apr** 24 new tests cover prefab variants, tags, overrides and the overlay. (commit [8d3f2f6](https://github.com/saworbit/hammerforge/commit/8d3f2f6cad48850d34cb0431d04d1745d7d26e96))

### Week of 23 Mar 2026

#### Added

- **29 Mar** Quick Play validates the player spawn, offers to fix one stuck in geometry or floating, and creates a spawn when none exists. (commit [0b90e2b](https://github.com/saworbit/hammerforge/commit/0b90e2b9805d07573bff5bdec14f515d876024fd))
- **28 Mar** A thumbnail texture browser with search, pattern and color filters and Favorites, plus a Texture Picker eyedropper on T. (commit [534ccd3](https://github.com/saworbit/hammerforge/commit/534ccd3358e7c435b10f66bb469664d41a9dbc3e))
- **28 Mar** Polygon (P) draws convex prism brushes and Path (;) lays box brushes along waypoints; vertex editing gains edge mode, edge split and merge. (commit [df719b6](https://github.com/saworbit/hammerforge/commit/df719b6527800e5d420671ee768de89afa154405))
- **27 Mar** Prefabs save and place brush and entity groups as `.hfprefab` files, and a five-step tutorial replaces the welcome panel. (commit [8c87ed4](https://github.com/saworbit/hammerforge/commit/8c87ed4318a7223edb86e47132a51d7eddce8f0f))
- **27 Mar** The Carve (Ctrl+Shift+R), Measure (M) and Decal (N) tools arrive, along with raise, lower, smooth and flatten terrain sculpt brushes. (commit [a7d5d41](https://github.com/saworbit/hammerforge/commit/a7d5d41764b584aecf6e08740293c150b5689405))
- **26 Mar** Snapping can target brush corners and centers as well as the grid, and a failed Hollow or Clip explains why and how to fix it. (commit [af2ea11](https://github.com/saworbit/hammerforge/commit/af2ea1196f0bee537faa2305327d3cff270e4f63))
- **24 Mar** A colored banner shows the current tool and drag step, and toast notifications report save, load, export and bake results. (commit [6224b00](https://github.com/saworbit/hammerforge/commit/6224b001078082d989448fd1731fb2b21ce83cb8))
- **24 Mar** 150 prototype textures (15 patterns in 10 colors) ship with the plugin, and Load Prototypes adds them all to the palette. (commit [dfede0f](https://github.com/saworbit/hammerforge/commit/dfede0f67797356a3e1cf247956db4d833e6ab24))
- **23 Mar** Keyboard shortcuts load from `user://hammerforge_keymap.json`, so they can be rebound, and toolbar labels follow the bindings. (commit [6e43326](https://github.com/saworbit/hammerforge/commit/6e43326d0b9ea50cbb927477102a69f011dfefb2))
- **23 Mar** Grid snap, autosave interval, recent files and collapsed sections persist across sessions in `user://hammerforge_prefs.json`. (commit [6e43326](https://github.com/saworbit/hammerforge/commit/6e43326d0b9ea50cbb927477102a69f011dfefb2))
- **23 Mar** Custom tools declare their settings, and the dock builds checkboxes, spin boxes and other controls for them. (commit [6e43326](https://github.com/saworbit/hammerforge/commit/6e43326d0b9ea50cbb927477102a69f011dfefb2))
- **23 Mar** The dock status bar names the active tool and shows when you are dragging or extruding. (commit [6e43326](https://github.com/saworbit/hammerforge/commit/6e43326d0b9ea50cbb927477102a69f011dfefb2))
- **23 Mar** A selected entity's properties appear as a form of typed fields built from its definition, synced with the Inspector. (commit [f6a179f](https://github.com/saworbit/hammerforge/commit/f6a179f43631c97464f734e7d1750269aa48d797))
- **23 Mar** The duplicator makes a set number of copies of selected brushes, each offset a step further. (commit [f6a179f](https://github.com/saworbit/hammerforge/commit/f6a179f43631c97464f734e7d1750269aa48d797))
- **23 Mar** `.map` export can write Valve 220 as well as classic Quake format, and now includes entity properties. (commit [f6a179f](https://github.com/saworbit/hammerforge/commit/f6a179f43631c97464f734e7d1750269aa48d797))
- **23 Mar** Custom editor tools placed in `res://addons/hammerforge/tools/` load at startup through a new tool registry. (commit [f6a179f](https://github.com/saworbit/hammerforge/commit/f6a179f43631c97464f734e7d1750269aa48d797))

#### Changed

- **24 Mar** Hollow, Clip and the other selection tools appear in the Brush tab when brushes are selected; paint and material panels update instantly. (commit [b03e8db](https://github.com/saworbit/hammerforge/commit/b03e8db4fb165df06c8db231e3ba97ee6edfa0db))
- **24 Mar** The Manage tab's Actions keep only floor, cuts and clear, and the toolbar uses one-character labels with tooltips. (commit [b03e8db](https://github.com/saworbit/hammerforge/commit/b03e8db4fb165df06c8db231e3ba97ee6edfa0db))
- **24 Mar** Dock sections collapse, with separators and indented content, and remember their state across sessions. (commit [b03e8db](https://github.com/saworbit/hammerforge/commit/b03e8db4fb165df06c8db231e3ba97ee6edfa0db))
- **24 Mar** Wider +/- buttons, even label widths and a 3×2 UV Justify grid tidy the dock. (commit [b03e8db](https://github.com/saworbit/hammerforge/commit/b03e8db4fb165df06c8db231e3ba97ee6edfa0db))
- **23 Mar** Hollow, Clip, Floor and Ceiling buttons are disabled, and their shortcuts do nothing, while nothing is selected. (commit [6e43326](https://github.com/saworbit/hammerforge/commit/6e43326d0b9ea50cbb927477102a69f011dfefb2))
- **23 Mar** Custom tools get key presses before the built-in shortcuts, so they can take over a key. (commit [6e43326](https://github.com/saworbit/hammerforge/commit/6e43326d0b9ea50cbb927477102a69f011dfefb2))

#### Fixed

- **23 Mar** Duplicate arrays can still be removed after undo, redo or a state restore. (commit [f6a179f](https://github.com/saworbit/hammerforge/commit/f6a179f43631c97464f734e7d1750269aa48d797))
- **23 Mar** Making a duplicate array from brushes that already have one replaces the old array instead of orphaning it. (commit [f6a179f](https://github.com/saworbit/hammerforge/commit/f6a179f43631c97464f734e7d1750269aa48d797))
- **23 Mar** Choosing a built-in tool from the toolbar or with U or J switches off an active custom tool; it used to stay on. (commit [f6a179f](https://github.com/saworbit/hammerforge/commit/f6a179f43631c97464f734e7d1750269aa48d797))

#### Behind the scenes

- **24 Mar** `dock.tscn` shrinks to about 320 lines: tab shells, toolbar and autosave warning. (commit [b03e8db](https://github.com/saworbit/hammerforge/commit/b03e8db4fb165df06c8db231e3ba97ee6edfa0db))
- **23 Mar** Brush edits tag what needs rebuilding, groundwork for reconciling only changed geometry. (commit [6e43326](https://github.com/saworbit/hammerforge/commit/6e43326d0b9ea50cbb927477102a69f011dfefb2))
- **23 Mar** LevelRoot can batch its signals so a multi-brush change sends a single selection update. (commit [6e43326](https://github.com/saworbit/hammerforge/commit/6e43326d0b9ea50cbb927477102a69f011dfefb2))
- **23 Mar** Tests for keymaps, user preferences and dirty tags. (commit [6e43326](https://github.com/saworbit/hammerforge/commit/6e43326d0b9ea50cbb927477102a69f011dfefb2))
- **23 Mar** A document of architecture lessons from TrenchBroom and QuArK. (commit [f6a179f](https://github.com/saworbit/hammerforge/commit/f6a179f43631c97464f734e7d1750269aa48d797))
- **23 Mar** ROADMAP adds QuArK-inspired items: entity property forms, `.map` export adapters, the duplicator, a plugin API and bezier patches. (commit [f6a179f](https://github.com/saworbit/hammerforge/commit/f6a179f43631c97464f734e7d1750269aa48d797))
- **23 Mar** SPEC describes the planned declarative entity property forms. (commit [f6a179f](https://github.com/saworbit/hammerforge/commit/f6a179f43631c97464f734e7d1750269aa48d797))
- **23 Mar** The data portability doc outlines the planned multi-format `.map` export. (commit [f6a179f](https://github.com/saworbit/hammerforge/commit/f6a179f43631c97464f734e7d1750269aa48d797))
- **23 Mar** Contributor and user docs cover undo collation, transactions, signals, entity definitions, gestures and autosave failures. (commit [f6a179f](https://github.com/saworbit/hammerforge/commit/f6a179f43631c97464f734e7d1750269aa48d797))
- **23 Mar** The DEVELOPMENT test table shows actual counts: 308 tests across 19 files. (commit [f6a179f](https://github.com/saworbit/hammerforge/commit/f6a179f43631c97464f734e7d1750269aa48d797))

### Week of 16 Mar 2026

#### Added

- **22 Mar** The dock shows a red warning when an autosave fails to write, hiding it after 30 seconds. (commit [cddbb72](https://github.com/saworbit/hammerforge/commit/cddbb7274d9efa54d16082ab6e62b8483482f851))
- **22 Mar** Entity classes come from definitions in `entities.json`, with built-in defaults, and fill the brush entity class dropdown. (commit [cddbb72](https://github.com/saworbit/hammerforge/commit/cddbb7274d9efa54d16082ab6e62b8483482f851))

#### Changed

- **22 Mar** Nudges, resizes or paint strokes made within a second of each other collapse into one undo step. (commit [cddbb72](https://github.com/saworbit/hammerforge/commit/cddbb7274d9efa54d16082ab6e62b8483482f851))

#### Fixed

- **22 Mar** Rapid nudges, resizes and paint strokes merge into one undo step; each used to add its own entry. (commit [cddbb72](https://github.com/saworbit/hammerforge/commit/cddbb7274d9efa54d16082ab6e62b8483482f851))
- **22 Mar** Undo no longer merges whole-level steps with smaller ones, which could restore the wrong state. (commit [cddbb72](https://github.com/saworbit/hammerforge/commit/cddbb7274d9efa54d16082ab6e62b8483482f851))
- **22 Mar** The autosave warning no longer crashes when the dock closes before its timer runs out. (commit [cddbb72](https://github.com/saworbit/hammerforge/commit/cddbb7274d9efa54d16082ab6e62b8483482f851))
- **22 Mar** Reloading the material palette keeps every slot in place; a missing material used to shift the rest, pointing faces at the wrong one. (commit [cddbb72](https://github.com/saworbit/hammerforge/commit/cddbb7274d9efa54d16082ab6e62b8483482f851))
- **22 Mar** The brush entity class dropdown falls back to built-in classes when `entities.json` has only point entities; it used to be empty. (commit [cddbb72](https://github.com/saworbit/hammerforge/commit/cddbb7274d9efa54d16082ab6e62b8483482f851))
- **22 Mar** Tie to Entity no longer crashes when the class dropdown is empty; it falls back to func_detail. (commit [cddbb72](https://github.com/saworbit/hammerforge/commit/cddbb7274d9efa54d16082ab6e62b8483482f851))

#### Behind the scenes

- **22 Mar** Hollow and Clip run inside transactions that restore a snapshot on rollback. (commit [cddbb72](https://github.com/saworbit/hammerforge/commit/cddbb7274d9efa54d16082ab6e62b8483482f851))
- **22 Mar** LevelRoot signals brush, entity, selection, paint and save changes, and the UI listens instead of polling. (commit [cddbb72](https://github.com/saworbit/hammerforge/commit/cddbb7274d9efa54d16082ab6e62b8483482f851))
- **22 Mar** The material manager can save and load the palette as JSON and track which materials are unused. (commit [cddbb72](https://github.com/saworbit/hammerforge/commit/cddbb7274d9efa54d16082ab6e62b8483482f851))
- **22 Mar** A gesture base class gives new tools a shared shape for drag, commit and cancel input. (commit [cddbb72](https://github.com/saworbit/hammerforge/commit/cddbb7274d9efa54d16082ab6e62b8483482f851))

### Week of 23 Feb 2026

#### Added

- **26 Feb** Clip (Shift+X) splits a brush in two along an axis-aligned plane snapped to the grid. (commit [8a0560e](https://github.com/saworbit/hammerforge/commit/8a0560ea2d88c5f88db2d24ff12dacae80121dc1))
- **26 Feb** Entity I/O wires one entity's outputs to another's inputs, Source style, with parameter, delay and fire-once fields. (commit [8a0560e](https://github.com/saworbit/hammerforge/commit/8a0560ea2d88c5f88db2d24ff12dacae80121dc1))
- **26 Feb** `func_detail` brushes get a cyan tint and `trigger_*` brushes an orange one in the viewport. (commit [8a0560e](https://github.com/saworbit/hammerforge/commit/8a0560ea2d88c5f88db2d24ff12dacae80121dc1))
- **26 Feb** Hollow (Ctrl+H) turns a solid brush into a room of six walls with the thickness you set. (commit [8a0560e](https://github.com/saworbit/hammerforge/commit/8a0560ea2d88c5f88db2d24ff12dacae80121dc1))
- **26 Feb** Typing digits while drawing or extruding a brush sets an exact size; Enter applies it and Escape cancels. (commit [8a0560e](https://github.com/saworbit/hammerforge/commit/8a0560ea2d88c5f88db2d24ff12dacae80121dc1))
- **26 Feb** Tie to Entity tags brushes as func_detail, func_wall or trigger classes; detail and trigger brushes stay out of the structural bake. (commit [8a0560e](https://github.com/saworbit/hammerforge/commit/8a0560ea2d88c5f88db2d24ff12dacae80121dc1))
- **26 Feb** Move to Floor (Ctrl+Shift+F) and Move to Ceiling (Ctrl+Shift+C) snap selected brushes to the nearest surface. (commit [8a0560e](https://github.com/saworbit/hammerforge/commit/8a0560ea2d88c5f88db2d24ff12dacae80121dc1))
- **26 Feb** A Justify panel in the UV Editor aligns faces to Fit, Center, Left, Right, Top or Bottom, optionally as one surface. (commit [8a0560e](https://github.com/saworbit/hammerforge/commit/8a0560ea2d88c5f88db2d24ff12dacae80121dc1))
- **26 Feb** A "No LevelRoot" banner at the top of the dock says when no LevelRoot is found. (commit [46f905d](https://github.com/saworbit/hammerforge/commit/46f905d4ceab5c01158822f15d5ec489d042e8b0))

#### Changed

- **26 Feb** The dock goes from eight tabs to four: Brush, Paint, Entities and Manage. (commit [46f905d](https://github.com/saworbit/hammerforge/commit/46f905d4ceab5c01158822f15d5ec489d042e8b0))
- **26 Feb** The Build tab becomes the Brush tab, and bake options and editor toggles move to Manage. (commit [46f905d](https://github.com/saworbit/hammerforge/commit/46f905d4ceab5c01158822f15d5ec489d042e8b0))
- **26 Feb** Floor Paint, Surface Paint, Materials and UV merge into one Paint tab of collapsible sections. (commit [46f905d](https://github.com/saworbit/hammerforge/commit/46f905d4ceab5c01158822f15d5ec489d042e8b0))

#### Fixed

- **26 Feb** LevelRoot stays active when you click other scene nodes, so you no longer have to reselect it. (commit [46f905d](https://github.com/saworbit/hammerforge/commit/46f905d4ceab5c01158822f15d5ec489d042e8b0))
- **26 Feb** Rebuilding brushes no longer leaves stale references to nodes that were just removed. (commit [46f905d](https://github.com/saworbit/hammerforge/commit/46f905d4ceab5c01158822f15d5ec489d042e8b0))
- **26 Feb** `.map` export reports a failed write instead of failing silently. (commit [46f905d](https://github.com/saworbit/hammerforge/commit/46f905d4ceab5c01158822f15d5ec489d042e8b0))
- **26 Feb** `level_root.tscn` is back to a 79-line template; it had grown to 11,652 lines of saved face data. (commit [46f905d](https://github.com/saworbit/hammerforge/commit/46f905d4ceab5c01158822f15d5ec489d042e8b0))

#### Behind the scenes

- **26 Feb** ROADMAP.md lists the gaps against Hammer with a prioritized wave plan. (commit [8a0560e](https://github.com/saworbit/hammerforge/commit/8a0560ea2d88c5f88db2d24ff12dacae80121dc1))
- **26 Feb** A brush system guard that could never trigger now checks for fewer than two parts. (commit [46f905d](https://github.com/saworbit/hammerforge/commit/46f905d4ceab5c01158822f15d5ec489d042e8b0))
- **26 Feb** About 100 dock controls become plain vars instead of @onready, since code now creates them. (commit [46f905d](https://github.com/saworbit/hammerforge/commit/46f905d4ceab5c01158822f15d5ec489d042e8b0))
- **26 Feb** The baker reads faces through typed DraftBrush access instead of duck typing. (commit [46f905d](https://github.com/saworbit/hammerforge/commit/46f905d4ceab5c01158822f15d5ec489d042e8b0))
- **26 Feb** A code audit across 11 files removes duck typing and duplicated code, and swaps per-frame dock updates for signals. (commit [46f905d](https://github.com/saworbit/hammerforge/commit/46f905d4ceab5c01158822f15d5ec489d042e8b0))

### Week of 16 Feb 2026

#### Added

- **22 Feb** Visgroups are named groups, such as walls or detail, that you can show or hide; they save in the `.hflevel`. (commit [5be4d9f](https://github.com/saworbit/hammerforge/commit/5be4d9fe13bb6e7f32f5e85fa4b7c1059cc3c022))
- **22 Feb** Ctrl+G groups brushes and entities so they select and move together; Ctrl+U ungroups them. (commit [5be4d9f](https://github.com/saworbit/hammerforge/commit/5be4d9fe13bb6e7f32f5e85fa4b7c1059cc3c022))
- **22 Feb** Texture Lock keeps UV alignment when you move or resize a brush, and is on by default. (commit [5be4d9f](https://github.com/saworbit/hammerforge/commit/5be4d9fe13bb6e7f32f5e85fa4b7c1059cc3c022))
- **22 Feb** Cordon limits a bake to a box region, drawn as a yellow wireframe and settable from the selection. (commit [5be4d9f](https://github.com/saworbit/hammerforge/commit/5be4d9fe13bb6e7f32f5e85fa4b7c1059cc3c022))
- **16 Feb** Heightmap floors blend four terrain textures per layer, picked with Blend Slot in the Floor Paint tab. (commit [b3368b8](https://github.com/saworbit/hammerforge/commit/b3368b8d7aef3b3c7e5ec33c500d85caa3847a6e))
- **16 Feb** Floor paint streams by region, loading and unloading chunks from `.hfr` files saved beside the `.hflevel`. (commit [cd7d163](https://github.com/saworbit/hammerforge/commit/cd7d163c45db77f36eac62f66975b2c580973330))

#### Changed

- **16 Feb** `.hflevel` files save floor paint material IDs, blend weights, heightmaps, height scale and terrain slot settings. (commit [b3368b8](https://github.com/saworbit/hammerforge/commit/b3368b8d7aef3b3c7e5ec33c500d85caa3847a6e))

#### Behind the scenes

- **22 Feb** A GUT unit test suite covers visgroups, grouping, texture lock, cordon, the duplicator and `.map` export. (commit [5be4d9f](https://github.com/saworbit/hammerforge/commit/5be4d9fe13bb6e7f32f5e85fa4b7c1059cc3c022))
- **22 Feb** CI runs the GUT tests alongside gdformat and gdlint. (commit [5be4d9f](https://github.com/saworbit/hammerforge/commit/5be4d9fe13bb6e7f32f5e85fa4b7c1059cc3c022))

### Week of 9 Feb 2026

#### Added

- **15 Feb** Bake progress shows chunk status in the dock. (commit [f2b4cff](https://github.com/saworbit/hammerforge/commit/f2b4cff7f787f6c2b9423cf03b5533989d200440))
- **15 Feb** Bake Dry Run reports preflight counts and chunk estimates without baking. (commit [f2b4cff](https://github.com/saworbit/hammerforge/commit/f2b4cff7f787f6c2b9423cf03b5533989d200440))
- **15 Feb** Validate Level checks for common issues and can fix them automatically. (commit [f2b4cff](https://github.com/saworbit/hammerforge/commit/f2b4cff7f787f6c2b9423cf03b5533989d200440))
- **15 Feb** Bake and export check for missing dependencies first. (commit [f2b4cff](https://github.com/saworbit/hammerforge/commit/f2b4cff7f787f6c2b9423cf03b5533989d200440))
- **15 Feb** Autosave rotates through timestamped history files. (commit [f2b4cff](https://github.com/saworbit/hammerforge/commit/f2b4cff7f787f6c2b9423cf03b5533989d200440))
- **15 Feb** A Performance panel shows brush count, paint memory, chunks and bake time. (commit [f2b4cff](https://github.com/saworbit/hammerforge/commit/f2b4cff7f787f6c2b9423cf03b5533989d200440))
- **15 Feb** Editor preferences can be exported and imported. (commit [f2b4cff](https://github.com/saworbit/hammerforge/commit/f2b4cff7f787f6c2b9423cf03b5533989d200440))
- **15 Feb** Sample levels: a minimal scene and a stress test scene. (commit [f2b4cff](https://github.com/saworbit/hammerforge/commit/f2b4cff7f787f6c2b9423cf03b5533989d200440))

#### Fixed

- **15 Feb** Greying out dock controls no longer sets an invalid disabled property on spin boxes. (commit [f2b4cff](https://github.com/saworbit/hammerforge/commit/f2b4cff7f787f6c2b9423cf03b5533989d200440))

#### Behind the scenes

- **15 Feb** An install and upgrade guide, with steps to reset the cache. (commit [f2b4cff](https://github.com/saworbit/hammerforge/commit/f2b4cff7f787f6c2b9423cf03b5533989d200440))
- **15 Feb** A design constraints document makes tradeoffs explicit. (commit [f2b4cff](https://github.com/saworbit/hammerforge/commit/f2b4cff7f787f6c2b9423cf03b5533989d200440))
- **15 Feb** A data portability guide covers `.hflevel`, `.map` and `.glb`. (commit [f2b4cff](https://github.com/saworbit/hammerforge/commit/f2b4cff7f787f6c2b9423cf03b5533989d200440))
- **15 Feb** A demo clip checklist and naming convention doc. (commit [f2b4cff](https://github.com/saworbit/hammerforge/commit/f2b4cff7f787f6c2b9423cf03b5533989d200440))
- **15 Feb** A roadmap and contributing guidelines. (commit [f2b4cff](https://github.com/saworbit/hammerforge/commit/f2b4cff7f787f6c2b9423cf03b5533989d200440))
- **15 Feb** Undoing a brush delete restores it from a snapshot keyed by brush ID. (commit [f2b4cff](https://github.com/saworbit/hammerforge/commit/f2b4cff7f787f6c2b9423cf03b5533989d200440))
- **15 Feb** Brushes made by direct placement get stable brush IDs. (commit [f2b4cff](https://github.com/saworbit/hammerforge/commit/f2b4cff7f787f6c2b9423cf03b5533989d200440))
- **15 Feb** Editor actions share one undo/redo helper built on state snapshots. (commit [f2b4cff](https://github.com/saworbit/hammerforge/commit/f2b4cff7f787f6c2b9423cf03b5533989d200440))

### Week of 2 Feb 2026

#### Added

- **8 Feb** Extrude Up (U) and Extrude Down (J) drag a new box brush out of any brush face, inheriting its material. (commit [029d048](https://github.com/saworbit/hammerforge/commit/029d048bf6ad80c19f0dfba173eee8a64ab27da3))
- **8 Feb** Floor paint layers can carry an imported or noise-generated heightmap, with blend painting, ramps and stairs between layers, and foliage. (commit [a710fd3](https://github.com/saworbit/hammerforge/commit/a710fd3439697996b34888b3458f1e6e7b1c863f))
- **7 Feb** Floor Paint offers a Square or Circle brush shape. (commit [fe12987](https://github.com/saworbit/hammerforge/commit/fe129877f5694aa5ae06c9159c82fe12de466036))
- **7 Feb** The shortcut HUD changes with the current tool and mode. (commit [2d0063a](https://github.com/saworbit/hammerforge/commit/2d0063a9e75c7bd43d834834dacd43f680f9f919))
- **7 Feb** Every dock control has a tooltip. (commit [2d0063a](https://github.com/saworbit/hammerforge/commit/2d0063a9e75c7bd43d834834dacd43f680f9f919))
- **7 Feb** The status bar shows how many brushes are selected. (commit [2d0063a](https://github.com/saworbit/hammerforge/commit/2d0063a9e75c7bd43d834834dacd43f680f9f919))
- **7 Feb** Paint tool shortcuts: B Brush, E Erase, R Rect, L Line, K Bucket. (commit [2d0063a](https://github.com/saworbit/hammerforge/commit/2d0063a9e75c7bd43d834834dacd43f680f9f919))
- **7 Feb** Pending cuts show orange-red with a strong glow, apart from applied subtract brushes. (commit [2d0063a](https://github.com/saworbit/hammerforge/commit/2d0063a9e75c7bd43d834834dacd43f680f9f919))
- **7 Feb** Status messages are color-coded for errors and warnings and clear after a timeout. (commit [2d0063a](https://github.com/saworbit/hammerforge/commit/2d0063a9e75c7bd43d834834dacd43f680f9f919))
- **7 Feb** The HUD shows the current axis lock, such as [X Locked]. (commit [2d0063a](https://github.com/saworbit/hammerforge/commit/2d0063a9e75c7bd43d834834dacd43f680f9f919))
- **6 Feb** A per-face material palette, with a face selection mode. (commit [f1d956f](https://github.com/saworbit/hammerforge/commit/f1d956fb7df1a9c4f433e8bfd0a61453a9de49b3))
- **6 Feb** A sample material, `materials/test_mat.tres`, for trying out the palette. (commit [f1d956f](https://github.com/saworbit/hammerforge/commit/f1d956fb7df1a9c4f433e8bfd0a61453a9de49b3))
- **6 Feb** A UV editor for editing each face's UVs. (commit [f1d956f](https://github.com/saworbit/hammerforge/commit/f1d956fb7df1a9c4f433e8bfd0a61453a9de49b3))
- **6 Feb** Surface paint adds per-face paint layers, with a texture picker. (commit [f1d956f](https://github.com/saworbit/hammerforge/commit/f1d956fb7df1a9c4f433e8bfd0a61453a9de49b3))
- **6 Feb** Bake option Use Face Materials bakes per-face materials without CSG. (commit [f1d956f](https://github.com/saworbit/hammerforge/commit/f1d956fb7df1a9c4f433e8bfd0a61453a9de49b3))

#### Changed

- **8 Feb** Floor paint layers with a heightmap build a displaced mesh instead of a CSG brush. (commit [a710fd3](https://github.com/saworbit/hammerforge/commit/a710fd3439697996b34888b3458f1e6e7b1c863f))
- **8 Feb** Generated heightmap floors sit under `LevelRoot/Generated/HeightmapFloors`. (commit [a710fd3](https://github.com/saworbit/hammerforge/commit/a710fd3439697996b34888b3458f1e6e7b1c863f))
- **7 Feb** A failed bake says "Bake failed - check Output for details" instead of a generic Error. (commit [2d0063a](https://github.com/saworbit/hammerforge/commit/2d0063a9e75c7bd43d834834dacd43f680f9f919))
- **6 Feb** The dock gets separate Floor Paint and Surface Paint tabs. (commit [f1d956f](https://github.com/saworbit/hammerforge/commit/f1d956fb7df1a9c4f433e8bfd0a61453a9de49b3))
- **6 Feb** Paint Mode can target floor paint or surface paint. (commit [f1d956f](https://github.com/saworbit/hammerforge/commit/f1d956fb7df1a9c4f433e8bfd0a61453a9de49b3))
- **6 Feb** `.hflevel` files save the material palette and per-face data. (commit [f1d956f](https://github.com/saworbit/hammerforge/commit/f1d956fb7df1a9c4f433e8bfd0a61453a9de49b3))

#### Fixed

- **8 Feb** Heightmap floors survive regeneration; changing height scale or generating noise again used to make the mesh vanish. (commit [a710fd3](https://github.com/saworbit/hammerforge/commit/a710fd3439697996b34888b3458f1e6e7b1c863f))
- **8 Feb** Walls no longer go missing while a heightmap floor is active. (commit [a710fd3](https://github.com/saworbit/hammerforge/commit/a710fd3439697996b34888b3458f1e6e7b1c863f))
- **8 Feb** Heightmap floors show default green and brown terrain colors and a cell grid; without textures they were a blank white pane. (commit [a710fd3](https://github.com/saworbit/hammerforge/commit/a710fd3439697996b34888b3458f1e6e7b1c863f))
- **7 Feb** The sample material `test_mat.tres` loads; a UTF-8 byte order mark stopped Godot reading it. (commit [f9441eb](https://github.com/saworbit/hammerforge/commit/f9441eb5844d06176a75074f9aaed65f22b96806))
- **7 Feb** A chunked bake no longer prints 59 "Invalid owner" errors. (commit [f9441eb](https://github.com/saworbit/hammerforge/commit/f9441eb5844d06176a75074f9aaed65f22b96806))
- **7 Feb** Navmesh `cell_height` defaults to 0.25 to match Godot's navigation map, ending mismatch warnings. (commit [f9441eb](https://github.com/saworbit/hammerforge/commit/f9441eb5844d06176a75074f9aaed65f22b96806))
- **7 Feb** Baked chunks, meshes, collision and navmesh all get proper editor ownership in one pass. (commit [f9441eb](https://github.com/saworbit/hammerforge/commit/f9441eb5844d06176a75074f9aaed65f22b96806))
- **7 Feb** Face paint blending runs every time; it used to run only when its weight image needed resizing. (commit [f9441eb](https://github.com/saworbit/hammerforge/commit/f9441eb5844d06176a75074f9aaed65f22b96806))
- **7 Feb** Background `.hflevel` saves log an error when the file cannot be opened or written. (commit [f9441eb](https://github.com/saworbit/hammerforge/commit/f9441eb5844d06176a75074f9aaed65f22b96806))

#### Behind the scenes

- **8 Feb** Docs cover the heightmap workflow, blend tool, connectors, foliage and bake integration. (commit [a710fd3](https://github.com/saworbit/hammerforge/commit/a710fd3439697996b34888b3458f1e6e7b1c863f))
- **7 Feb** CI checks every push and PR with gdformat and gdlint. (commit [f9441eb](https://github.com/saworbit/hammerforge/commit/f9441eb5844d06176a75074f9aaed65f22b96806))
- **7 Feb** `level_root.gd` splits from about 2,500 lines into a 1,100-line coordinator and eight subsystems. (commit [f9441eb](https://github.com/saworbit/hammerforge/commit/f9441eb5844d06176a75074f9aaed65f22b96806))
- **7 Feb** An input state machine replaces more than 18 loose drag and paint state variables. (commit [f9441eb](https://github.com/saworbit/hammerforge/commit/f9441eb5844d06176a75074f9aaed65f22b96806))
- **7 Feb** About 57 duck-typed calls in the plugin and dock become direct typed calls. (commit [f9441eb](https://github.com/saworbit/hammerforge/commit/f9441eb5844d06176a75074f9aaed65f22b96806))
- **7 Feb** `.hflevel` value encoding gets recursion depth limits and checks on nested arrays. (commit [f9441eb](https://github.com/saworbit/hammerforge/commit/f9441eb5844d06176a75074f9aaed65f22b96806))
- **7 Feb** The baker checks for null after mesh post-processing and texture creation. (commit [f9441eb](https://github.com/saworbit/hammerforge/commit/f9441eb5844d06176a75074f9aaed65f22b96806))
- **7 Feb** Plugin teardown uses queue_free with validity checks instead of free. (commit [f9441eb](https://github.com/saworbit/hammerforge/commit/f9441eb5844d06176a75074f9aaed65f22b96806))
- **7 Feb** Leftover Godot 3 Image.lock and unlock calls are gone from the face data code. (commit [f9441eb](https://github.com/saworbit/hammerforge/commit/f9441eb5844d06176a75074f9aaed65f22b96806))
- **7 Feb** Face paint blending caches texture images instead of fetching and resizing them each time. (commit [f9441eb](https://github.com/saworbit/hammerforge/commit/f9441eb5844d06176a75074f9aaed65f22b96806))
- **7 Feb** Screen bounds checks skip objects that are fully behind the camera. (commit [f9441eb](https://github.com/saworbit/hammerforge/commit/f9441eb5844d06176a75074f9aaed65f22b96806))
- **7 Feb** Spec, development guide, MVP guide and README describe the subsystem layout. (commit [f9441eb](https://github.com/saworbit/hammerforge/commit/f9441eb5844d06176a75074f9aaed65f22b96806))
- **7 Feb** Docs cover the dynamic HUD, tooltips, shortcuts and pending cut visuals. (commit [2d0063a](https://github.com/saworbit/hammerforge/commit/2d0063a9e75c7bd43d834834dacd43f680f9f919))
- **6 Feb** A texture and materials guide and a development and testing guide, plus updated README, spec, user and MVP docs. (commit [f1d956f](https://github.com/saworbit/hammerforge/commit/f1d956fb7df1a9c4f433e8bfd0a61453a9de49b3))

## [0.1.1] - 2026-02-05

**Highlights**

- Paint previews live while you drag, and paint layers save in `.hflevel` files.
- Painting at negative coordinates lands where you paint instead of in another quadrant.

The long write-ups, as first written: [changelog/0.1.1.md](changelog/0.1.1.md)

### Week of 2 Feb 2026

#### Added

- **5 Feb** Paint shows a live preview while dragging with Brush, Erase, Line and Rect. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** Paint layers save in `.hflevel` files. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))

#### Changed

- **5 Feb** Bucket fill gets improvements and guardrails. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** The paint preview updates generated floors and walls in real time. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** Paint radius 1 paints a single cell. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))

#### Fixed

- **5 Feb** Painting at negative coordinates lands where you paint instead of mirroring into another quadrant. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** The live paint preview shows while dragging instead of only on mouse-up. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))

#### Behind the scenes

- **5 Feb** The paint preview updates only dirty chunks and reuses its nodes instead of rebuilding them. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** Docs explain how to capture logs for errors Godot prints on exit. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** Docs reference the right entity icons instead of corrupt ones. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** README, spec and guides are refreshed for the paint system and its workflows. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))

## [0.1.0] - 2026-02-05

**Highlights**

- CAD-style brush drawing with a dozen shapes, pending subtract cuts and Bake.
- Entities defined in `entities.json`, an FPS playtest, and floor paint that builds floors and walls for you.

The long write-ups, as first written: [changelog/0.1.0.md](changelog/0.1.0.md)

### Week of 2 Feb 2026

#### Added

- **5 Feb** The first click creates a LevelRoot if the scene has none. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** Resize handle drags snap to `grid_snap`. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** Bake can split the level into chunks with `bake_chunk_size` (default 32). (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** Entities live under LevelRoot/Entities, stay selectable and are left out of the bake. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** Entity definitions load from `res://addons/hammerforge/entities.json`. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** Entities get schema-driven properties with Inspector dropdowns; older `entity_data` still loads. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** Entities show editor-only billboard or mesh previews defined in `entities.json`. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** A `player_start` entity marks where the playtest player starts. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** A running playtest can hot-reload, signalled through `res://.hammerforge/reload.lock`. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** Floor paint draws on grid-based layers and generates floors and walls automatically. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** The dock has paint tools (Brush, Erase, Rect, Line, Bucket), a radius control and a layer picker. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** Paint layers and their chunk data save in `.hflevel` files. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **2 Feb** Playtests use an FPS controller with sprint, crouch, jump, head-bob, FOV stretch and coyote time. (commit [8e59854](https://github.com/saworbit/hammerforge/commit/8e59854e99d412baded0c28e884e237068e01105))
- **2 Feb** A Playtest button bakes and launches the current scene. (commit [8e59854](https://github.com/saworbit/hammerforge/commit/8e59854e99d412baded0c28e884e237068e01105))

#### Changed

- **5 Feb** Paint Mode drives floor paint; painting materials waits for a later pass. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **3 Feb** Drag-marquee selection is turned off in the viewport to avoid input conflicts. (commit [1ace8c6](https://github.com/saworbit/hammerforge/commit/1ace8c6a9e32da5be274ef37e6ef0f2ea835f7c5))

#### Fixed

- **2 Feb** Playtests wait for the scene tree to be ready before spawning the player, avoiding transform warnings. (commit [8e59854](https://github.com/saworbit/hammerforge/commit/8e59854e99d412baded0c28e884e237068e01105))
- **2 Feb** Playtest bakes before hiding draft geometry, so brushes show up in the game. (commit [8e59854](https://github.com/saworbit/hammerforge/commit/8e59854e99d412baded0c28e884e237068e01105))

#### Behind the scenes

- **5 Feb** Generated paint geometry keeps stable IDs, so repainting updates nodes instead of recreating them. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** Docs cover the floor paint workflow, layers and saving. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **5 Feb** README, spec and guides are refreshed for floor paint, layers and logs. (commit [ccb12ed](https://github.com/saworbit/hammerforge/commit/ccb12ed5754ca167e7d19fb5931a23342e90107c))
- **3 Feb** Docs describe selection limits and that drag-marquee is off in the viewport. (commit [1ace8c6](https://github.com/saworbit/hammerforge/commit/1ace8c6a9e32da5be274ef37e6ef0f2ea835f7c5))

### Week of 26 Jan 2026

#### Added

- **1 Feb** A dock button creates a DraftEntity. (commit [88aa499](https://github.com/saworbit/hammerforge/commit/88aa4992be92591623075331e45df2f37fdf76b7))
- **31 Jan** Draft brushes get a face-handle resize gizmo in the viewport that works with undo and redo. (commit [d608891](https://github.com/saworbit/hammerforge/commit/d608891bb945215817918404e965d07094286b3b))
- **31 Jan** Pyramids, prisms and platonic solids preview as line meshes while drafting. (commit [d608891](https://github.com/saworbit/hammerforge/commit/d608891bb945215817918404e965d07094286b3b))
- **30 Jan** Brushes draw CAD-style: drag out the base, then set the height and click again to commit. (commit [0c6846c](https://github.com/saworbit/hammerforge/commit/0c6846c16548fe4de0c10d548bb1869f2b5b20d8))
- **30 Jan** While drawing, Shift makes a square base, Shift+Alt a cube and Alt changes height only. (commit [0c6846c](https://github.com/saworbit/hammerforge/commit/0c6846c16548fe4de0c10d548bb1869f2b5b20d8))
- **30 Jan** Drawing can lock to the X, Y or Z axis. (commit [0c6846c](https://github.com/saworbit/hammerforge/commit/0c6846c16548fe4de0c10d548bb1869f2b5b20d8))
- **30 Jan** The dock has a Draw/Select tool toggle. (commit [0c6846c](https://github.com/saworbit/hammerforge/commit/0c6846c16548fe4de0c10d548bb1869f2b5b20d8))
- **30 Jan** Settings, Presets and Actions in the dock are collapsible sections. (commit [88aea62](https://github.com/saworbit/hammerforge/commit/88aea62cc25333d38df91dcbb21091c0b24410fb))
- **30 Jan** A dock dropdown picks physics layer presets for baked collision. (commit [ecbd1fc](https://github.com/saworbit/hammerforge/commit/ecbd1fc0c9a53d73c3d9cf23997dc7991d3b6784))
- **30 Jan** A live brush count indicator shows performance warnings as the count grows. (commit [ecbd1fc](https://github.com/saworbit/hammerforge/commit/ecbd1fc0c9a53d73c3d9cf23997dc7991d3b6784))
- **30 Jan** LevelRoot has its own icon in the scene tree. (commit [ecbd1fc](https://github.com/saworbit/hammerforge/commit/ecbd1fc0c9a53d73c3d9cf23997dc7991d3b6784))
- **30 Jan** Paint Mode applies the active material to brushes you click in the viewport. (commit [a2c0c0a](https://github.com/saworbit/hammerforge/commit/a2c0c0aee8544f45811e82652c5915889855d470))
- **30 Jan** The dock has an active material picker that opens `.tres` and `.material` files. (commit [a2c0c0a](https://github.com/saworbit/hammerforge/commit/a2c0c0aee8544f45811e82652c5915889855d470))
- **30 Jan** Select highlights the brush under the cursor with a box wireframe. (commit [a2c0c0a](https://github.com/saworbit/hammerforge/commit/a2c0c0aee8544f45811e82652c5915889855d470))
- **30 Jan** A prefab factory builds advanced shapes from a dynamic shape palette. (commit [ca6b812](https://github.com/saworbit/hammerforge/commit/ca6b812d69eb1798c0b82537490e773cf2d15830))
- **30 Jan** New brush shapes: wedge, pyramid, prism, cone, sphere, ellipsoid, capsule, torus and the platonic solids. (commit [ca6b812](https://github.com/saworbit/hammerforge/commit/ca6b812d69eb1798c0b82537490e773cf2d15830))
- **30 Jan** Capsule, torus and platonic solid shapes scale to the brush's dimensions. (commit [afc59aa](https://github.com/saworbit/hammerforge/commit/afc59aa93dd8031f552e04bb433bbf4b5af8547c))
- **30 Jan** Shift-click adds to the selection, Delete removes brushes and Ctrl+D duplicates them. (commit [0c6846c](https://github.com/saworbit/hammerforge/commit/0c6846c16548fe4de0c10d548bb1869f2b5b20d8))
- **30 Jan** Arrow keys and PageUp/PageDown nudge selected brushes. (commit [0c6846c](https://github.com/saworbit/hammerforge/commit/0c6846c16548fe4de0c10d548bb1869f2b5b20d8))
- **30 Jan** A Create Floor button sets up a raycast surface to draw on in one click. (commit [0c6846c](https://github.com/saworbit/hammerforge/commit/0c6846c16548fe4de0c10d548bb1869f2b5b20d8))
- **30 Jan** Subtract cuts stay pending with Apply and Clear buttons, and Bake applies them automatically. (commit [0c6846c](https://github.com/saworbit/hammerforge/commit/0c6846c16548fe4de0c10d548bb1869f2b5b20d8))
- **30 Jan** Cylinder brushes and a grid snap control arrive, and draw previews tint by Add or Subtract. (commit [0c6846c](https://github.com/saworbit/hammerforge/commit/0c6846c16548fe4de0c10d548bb1869f2b5b20d8))
- **30 Jan** Committed cuts can be frozen and restored, and Bake gains multi-mesh output, a status readout and a collision layer control. (commit [ecdd766](https://github.com/saworbit/hammerforge/commit/ecdd7661bfdb8108b4f84c172305c37ac2911c78))

#### Changed

- **30 Jan** With a brush already selected, Select gives way to Godot's built-in gizmos. (commit [a2c0c0a](https://github.com/saworbit/hammerforge/commit/a2c0c0aee8544f45811e82652c5915889855d470))

#### Fixed

- **31 Jan** Baked collision comes from Add brushes only; Subtract brushes are left out. (commit [d608891](https://github.com/saworbit/hammerforge/commit/d608891bb945215817918404e965d07094286b3b))
- **30 Jan** Selection picks cylinders and rotated brushes. (commit [0c6846c](https://github.com/saworbit/hammerforge/commit/0c6846c16548fe4de0c10d548bb1869f2b5b20d8))
- **30 Jan** Dragging height follows the mouse: moving up makes the brush taller. (commit [0c6846c](https://github.com/saworbit/hammerforge/commit/0c6846c16548fe4de0c10d548bb1869f2b5b20d8))
- **30 Jan** Deleting brushes is guarded so it no longer raises "Remove Node(s)" errors. (commit [0c6846c](https://github.com/saworbit/hammerforge/commit/0c6846c16548fe4de0c10d548bb1869f2b5b20d8))
- **30 Jan** The dock loads reliably; invalid parent paths used to break it. (commit [0c6846c](https://github.com/saworbit/hammerforge/commit/0c6846c16548fe4de0c10d548bb1869f2b5b20d8))
- **30 Jan** Committed cuts bake with neutral materials, so carved faces no longer inherit the red preview. (commit [ecdd766](https://github.com/saworbit/hammerforge/commit/ecdd7661bfdb8108b4f84c172305c37ac2911c78))

#### Behind the scenes

- **1 Feb** Docs explain using Godot's built-in 4-view layout. (commit [96cd77a](https://github.com/saworbit/hammerforge/commit/96cd77a348a88a9e883805e9e63edfe7b286498f))
- **1 Feb** README, user guide, MVP guide and spec cover chunked baking and the entity workflow. (commit [96cd77a](https://github.com/saworbit/hammerforge/commit/96cd77a348a88a9e883805e9e63edfe7b286498f))
- **30 Jan** The docs gain a user guide and a fuller LevelRoot explanation. (commit [0c6846c](https://github.com/saworbit/hammerforge/commit/0c6846c16548fe4de0c10d548bb1869f2b5b20d8))
