# Glossary

One name for each idea. Each entry says what the word means, where you meet it in
HammerForge, the words not to use for it, and the code's own name where that
differs on purpose. A pull request that adds an idea adds its term here, and a
test fails when a label, tooltip, toast, message or page uses a word an entry
lists under **Don't use**.

## Building

### Brush
A convex solid the level is built from, drawn with Draw, Polygon or Path, or made by
a structure, a prefab or an import.

- **In HammerForge:** the Build tab, the viewport, Validate and the Agent Bridge's
  `hf_get_brushes`.
- **Code name:** `DraftBrush`.

### Solid brush
A brush that adds its volume to the level. One of the two kinds a draw makes; the
Build tab's **Solid** button and Toggle Solid / Cut (`Q`) choose it.

- **In HammerForge:** the Build tab, the palette, the context toolbar, Validate.
- **Don't use:** additive brush, add brush, union brush.
- **Code name:** `CSGShape3D.OPERATION_UNION`. The bridge takes `"union"` for it.

### Cut brush
A brush that removes its volume from the solid brushes it overlaps, for a doorway or
a window. The Build tab's **Cut** button chooses it. A cut waits as a pending cut
until it is applied.

- **In HammerForge:** the Build tab, Validate ("Cut brush cuts no solid brush"),
  Apply Pending Cuts and Commit Cuts.
- **Don't use:** subtractive brush, subtract brush, subtraction brush, cutout brush,
  negative brush.
- **Code name:** `CSGShape3D.OPERATION_SUBTRACTION`. The bridge takes `"subtract"`
  for it.

### Pending cut
A cut brush drawn and not yet applied. It shows as an overlay and changes nothing
until **Apply Pending Cuts**.

- **In HammerForge:** the Build tab, the palette, Validate.

### Commit
To make pending cuts final: **Commit Cuts** keeps the cut brushes as hidden
cutters the bake reads, so the solid brushes stay editable.

- **In HammerForge:** the palette, the Build tab.

### Cut preview
The live view of what a cut brush will remove from the brushes it overlaps,
before the cut is applied.

- **In HammerForge:** the Manage tab and the Console's Controls.
- **Don't use:** subtract preview.
- **Code name:** `subtract_preview`.

### Carve
Cut one brush's shape out of every brush it overlaps, replacing them with their
pieces and using the carver up. Not the same as a cut brush, which waits and can be
undone by moving it.

- **In HammerForge:** the palette, the context toolbar, `Ctrl+Shift+R`.

### Hollow
Shell a brush into walls of a set thickness, inward from each face.

- **In HammerForge:** the palette, Selection Tools, `Ctrl+H`.

### Clip
Cut the selected brushes along a plane and keep one side or both.

- **In HammerForge:** the Clip tool, the palette.

### Merge
Join brushes into the one convex brush they make together. Refused when they do
not touch or would make an L.

- **In HammerForge:** the palette, the context toolbar.

### Hull
One brush that is the convex hull of the selected brushes' corners, or of points
clicked with the Hull tool, whether they touch or not.

- **In HammerForge:** Hull of Selection and the Hull tool.

### Sweep
A run of brushes made by carrying picked faces along a straight run, an arc or an
S bend, one convex brush per piece, the pieces meeting face to face. A sweep is a
structure: select a piece and **Update Sweep** builds it again with new values.

- **In HammerForge:** Sweep Faces in the palette, its pivot and end handles in the
  viewport, the Build tab's Structure section.
- **Not to be confused with:** Sweep Select, which picks brushes and makes none.

### Sweep Select
Holding its key, I by default, and dragging in the Select tool: each brush or face
the pointer passes over joins the selection, or leaves it when the first one passed
was selected already.

- **In HammerForge:** the Select tool and Face Select, the shortcut HUD.
- **Code name:** `HFSweepSelect`, and `sweep_select_hold` in the keymap.

### Grid angle
How far the floor grid is turned about up, so a part of a level set at an angle is
drawn square to it. 0 is the world's grid.

- **In HammerForge:** the Angle field beside the grid size, Align Grid to Selection
  with an edge or a turned brush, the HUD's grid label, Reset Grid.
- **Code name:** `HFGridSystem.turn_degrees`.

### Face
One flat side of a brush, with its own material and texture settings.

- **In HammerForge:** Face Select, the Paint tab, the UV editor.
- **Code name:** `FaceData`.

### Face selection
The faces picked in Face Select, which the Paint tab's buttons and boxes edit.

- **In HammerForge:** Face Select, the Paint tab.

### Structure
A shape built from settings and kept editable: stairs, a spiral stair, an arch,
a dome, a ring, a door frame, a trim run or a sweep. Change its settings and the pieces are built again;
Detach makes them plain brushes.

- **In HammerForge:** the Build tab's Structure section, the palette, the bridge's
  `update_structure` and `detach_structure`.
- **Don't use:** generator.
- **Code name:** generator (`HFGenerator`, `HFGeneratorSystem`), the record that
  keeps a structure editable.

## Materials and texture

### Material
What a face is drawn with: a texture and how it shades.

- **In HammerForge:** the Paint tab, the material browser.

### Palette
The level's list of materials, by slot. A face stores the slot it wears.

- **In HammerForge:** the material browser's Palette view, Replace Material.

### Active Material
The whole brush material every new brush is made with.

- **In HammerForge:** the Build tab.

### Texture group
Faces linked into one surface, which share one mapping, so an edit to any of them
is an edit to all.

- **In HammerForge:** **Link** in the Paint tab, called Linked Surfaces in the
  guide.
- **Code name:** `uv_group`.

### Floor paint
Painting the floor by grid cells on a paint layer, with walls raised round what is
painted.

- **In HammerForge:** the Paint tab's floor tools.

### Paint layer
One layer of floor paint, at its own height.

- **In HammerForge:** the Paint tab.

### Connector
A ramp or a step that joins two paint layers.

- **In HammerForge:** the Paint tab.

### Sculpt
Heights laid over a four cornered face to make it uneven, for terrain.

- **In HammerForge:** the Paint tab's sculpt tools.
- **Code name:** displacement (`HFDisplacementData`).

## Objects

### Prefab
A saved piece of a level, brushes and entities with their wiring, that can be
placed again.

- **In HammerForge:** the prefab library, Save Prefab, Quick Save Prefab.

### Prefab copy
A prefab placed in a level. A linked copy follows its prefab when it is pushed or
pulled.

- **In HammerForge:** the prefab library, Unlink Prefab Copy.
- **Code name:** instance (`HFPrefab` instance records).

### Variant
One of a prefab's alternative versions, which Cycle Variant switches a copy
between.

- **In HammerForge:** the palette, the prefab library.

### Visgroup
A named set of brushes and entities that is shown, hidden or locked together. A
brush can be in several.

- **In HammerForge:** the Manage tab's Visgroups & Groups.

### Group
Brushes and entities that select and move together, under a name. A brush is in
one group, and a group can be inside another. Opening a group lets its members be
picked one at a time. A visgroup decides what is seen; a group decides what is
picked up together.

- **In HammerForge:** the Manage tab's Visgroups & Groups and its Groups list,
  Group and Ungroup, Open Group.

### View Filters
The editor's own way to hide a kind of thing, such as triggers or lights, without
a visgroup. Never saved with the level, and ignored by the bake.

- **In HammerForge:** the Manage tab.

### Brush entity
A brush that is an entity, a trigger, a door or a button, with a class and
properties.

- **In HammerForge:** the Entity tab, Tie to Entity.

### Point entity
An entity at a point, with no brush: a light, a sound, a prop, a spawn or a piece of
logic.

- **In HammerForge:** the Entity tab, the Entities palette.
- **Code name:** `DraftEntity`.

### Output
What an entity sends when something happens to it, aimed at another entity's
input.

- **In HammerForge:** the I/O section of the Entity tab.

### Input
What an entity does when an output reaches it.

- **In HammerForge:** the I/O section of the Entity tab.

### Wire
One connection from an output to an input, drawn between the two in the viewport.

- **In HammerForge:** the I/O section, the viewport's I/O wires.

### Spawn
Where the player starts in a playtest.

- **In HammerForge:** the Test tab, the spawn entity.

### Dimension
A length kept in the level. Each end is attached to the brush vertex, edge middle
or face centre it lies on, or is a point of its own, and a check can hold the
length to the player's sizes or to a value. Like a note, it is never baked or
exported.

- **In HammerForge:** K in the Measure tool, Keep Ruler as Dimension, Validate.

## The level and its files

### LevelRoot
The node a level lives under, which holds its brushes, entities and settings.

- **In HammerForge:** the scene tree.

### .hflevel
The level's own file, the source of truth for what a level holds.

- **In HammerForge:** Save and Load in the Manage tab, autosave.

### Autosave
A copy of the `.hflevel` written in the background as you work.

- **In HammerForge:** the Console's Controls.

### Cordon
A box that limits what a partial bake takes.

- **In HammerForge:** the Manage tab.

### Bake
Turning the brushes into the meshes, collision and lighting a game runs.

- **In HammerForge:** the Bake section, Bake, Bake Selected.

### Bake profile
A saved set of bake settings, to switch between fast and full bakes.

- **In HammerForge:** the Bake section.

### Chunk
One piece of a level the bake splits a big level into.

- **In HammerForge:** the Bake section.

### Collision
The solid shape the player bumps into, which the bake makes from the brushes.

- **In HammerForge:** the Bake section, clip brushes.

### Playtest
Running the level from the editor to walk round it.

- **In HammerForge:** the Test tab, Quick Play.

### Validate
The check that lists problems in the level, each with a way to fix it.

- **In HammerForge:** the Manage tab, `Ctrl+Shift+Enter`.

## Tools and history

### Console
The dock panel with the log and the level's Controls.

- **In HammerForge:** the dock.

### Agent Bridge
The connection an agent drives HammerForge through, by MCP.

- **In HammerForge:** the Agent Bridge guide.

### Revision
The bridge's count of changes to a level, so an agent can tell when it moved.

- **In HammerForge:** the Agent Bridge.

### Undo step
One entry in the undo history. Most commands make one; a run of quick nudges
merges into one.

- **In HammerForge:** `Ctrl+Z`, the Undo History browser.

### Adjust Last
Changing the settings of the command that just ran. Its step is made again with
the new values, so the history still holds one step for it.

- **In HammerForge:** the Adjust panel in the viewport's corner, Adjust Last in
  the palette.

### Repeat Run
Every command, move and turn since the selection last changed by hand, played
again on what is selected now as one undo step. Repeat Last Command plays only
the last command.

- **In HammerForge:** the palette.

### Guide
A dotted line from a marked snap point along a world axis. A point placed near
one lands on it, or where two cross.

- **In HammerForge:** rest the pointer on a snap point, Track Point for Guides,
  Clear Guides.
