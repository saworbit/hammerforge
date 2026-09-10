# Changelog

All notable changes to this project will be documented in this file.
The format is based on Keep a Changelog, and this project follows semantic versioning.

## [Unreleased]
### Added
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
