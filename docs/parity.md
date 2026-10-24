# Parity with the classic brush editors

How much of the tool set of Hammer and TrenchBroom HammerForge covers, by
the names of their tools and menu actions. Each is mapped to the
HammerForge commands that do its job, to a note where Godot or a panel
does it, or to nothing yet. A line not planned is left out of the share.

This page is written by `tools/gen_parity.py` from
`docs/data/classic-editor-tools.txt` and the command registry, and CI
fails when it is out of date or names a command that is gone (#1707).
Change the catalog, not this page.

Generated 2026-10-25.

**Covered: 132 of 137, 96%.**

| Area | Covered | Share |
|---|---|---|
| Selection | 17 of 19 | 89% |
| Brush creation | 21 of 21 | 100% |
| Transform | 13 of 13 | 100% |
| Boolean and clipping | 8 of 8 | 100% |
| Vertex editing | 9 of 9 | 100% |
| Texturing | 28 of 30 | 93% |
| Entities | 11 of 11 | 100% |
| Visibility and layers | 7 of 7 | 100% |
| Problems and compiling | 5 of 6 | 83% |
| View | 8 of 8 | 100% |
| Files | 5 of 5 | 100% |

## Selection

| Tool | HammerForge |
|---|---|
| Selection tool | `tool_select` |
| Select All | `select_all` |
| Select None | `deselect_all` |
| Invert Selection | `invert_selection` |
| Select Touching | `select_touching` |
| Select Inside | `select_inside` |
| Select Partially Inside | `select_partly_inside` |
| Select Tall | `select_column` |
| Select Matching Texture | `select_similar` |
| Select by Line Number | Not yet |
| Find Entities | `quick_select` |
| Selection Filter | `selection_filter` |
| Grow Selection | `grow_selection` |
| Quick Hide | `hide_selection` |
| Quick Hide Unselected | `isolate_selection` |
| Quick Unhide | `show_hidden` |
| Group | `group` |
| Ungroup | `ungroup` |
| Ignore Groups | Not yet |

## Brush creation

| Tool | HammerForge |
|---|---|
| Block Tool | `tool_draw` |
| Create Brush Tool | `tool_draw` |
| Block Primitive | `shape_box` |
| Cylinder Primitive | `shape_cylinder` |
| Sphere Primitive | `shape_sphere` |
| Spike Primitive | `shape_cone` |
| Wedge Primitive | the Build tab's Shape list |
| Torus Primitive | the Build tab's Shape list |
| Arch | `create_arch` |
| Convex Brush from Points | `tool_hull` |
| Polygon Brush | `tool_polygon` |
| Duplicate | `duplicate` |
| Clone by Dragging | Shift with an arrow key duplicates and moves the copy |
| Copy | `copy` |
| Paste | `paste` |
| Paste Special | Duplicate Array repeats a copy in a line, a grid or a ring |
| Delete | `delete` |
| Undo | `undo` |
| Redo | `redo` |
| Repeat Last Command | `repeat_last_command` |
| Repeat Last Brush | `repeat_brush` |

## Transform

| Tool | HammerForge |
|---|---|
| Move Objects | the arrow keys nudge and Godot's move gizmo drags |
| Rotate 90 Degrees Clockwise | `rotate_cw` |
| Rotate 90 Degrees Counter-clockwise | `rotate_ccw` |
| Rotate Tool | Godot's own rotate gizmo |
| Scale Tool | Godot's scale gizmo and the brush resize handles |
| Shear Tool | `tool_shear`, `shear_selection` |
| Flip Objects | `flip_selection` |
| Mirror | `mirror_copy` |
| Transform Dialog | `offset_selection` |
| Snap Selected to Grid | `snap_to_grid` |
| Align Objects | `move_to_floor`, `move_to_ceiling` |
| Reset Rotation | `reset_rotation` |
| Pick Pivot | `pick_pivot` |

## Boolean and clipping

| Tool | HammerForge |
|---|---|
| Make Hollow | `hollow` |
| Carve | `carve` |
| CSG Subtract | `carve` |
| CSG Convex Merge | `merge`, `hull` |
| CSG Intersect | `intersect` |
| CSG Hollow | `hollow` |
| Clipping Tool | `tool_clip`, `clip` |
| Clip to a Face Plane | `clip_to_face` |

## Vertex editing

| Tool | HammerForge |
|---|---|
| Vertex Manipulation | `vertex_edit` |
| Vertex Tool | `vertex_submode` |
| Edge Tool | `edge_submode` |
| Face Tool | `tool_extrude_up`, `tool_extrude_down` |
| Snap Vertices to Grid | `vertex_snap_to_grid` |
| Merge Vertices | `vertex_merge` |
| Split Edge | `vertex_split_edge` |
| Make Convex | `vertex_clip_convex` |
| Scale Vertices | `vertex_scale` |

## Texturing

| Tool | HammerForge |
|---|---|
| Texture Application Tool | the Paint tab's Face Tools and UV Editor |
| Face Edit Sheet | the Paint tab's Face Tools and UV Editor |
| Texture Browser | the Material Browser in the Paint tab |
| Apply Current Texture | `apply_last_texture` |
| Apply Texture to Whole Brush | `apply_to_brush` |
| Lift Texture | `texture_picker` |
| Apply Texture and Alignment | `apply_picked_look` |
| Texture Lock | the Texture Lock box in the Build tab |
| UV Lock | the Texture Lock box in the Build tab |
| Justify Fit | `justify_fit` |
| Justify Left | `justify_left` |
| Justify Right | `justify_right` |
| Justify Top | `justify_top` |
| Justify Bottom | `justify_bottom` |
| Justify Center | `justify_center` |
| Align to World | `uv_align_world` |
| Align to Face | `uv_align_face` |
| Rotate Texture | `uv_rotate_90` |
| Flip Texture | `uv_flip_u`, `uv_flip_v` |
| Treat as One | `uv_link` |
| Wrap Texture | `uv_wrap` |
| Replace Textures | `replace_material` |
| Decal Tool | `tool_decal` |
| Overlay Tool | Not yet |
| Smoothing Groups | the UV Editor's Smoothing box |
| Nodraw Faces | `make_faces_hidden`, `hide_faces_against_solids` |
| Create Displacement | the Displacement section of Face Tools |
| Sculpt Displacement | the Displacement section of Face Tools |
| Paint Displacement Alpha | Not yet |
| Sew Displacements | the Displacement section of Face Tools |

## Entities

| Tool | HammerForge |
|---|---|
| Entity Tool | `place_entity_here` |
| Entity Browser | the Objects tab's entity palette |
| Object Properties | `entity_props` |
| Smart Property Editors | the Entity panel's typed editors, choices and flags among them |
| Tie to Entity | `make_brush_entity` |
| Move to World | `back_to_world` |
| Entity Connections | `entity_io`, `highlight_connected`, `cycle_io_wires` |
| Entity Report | the Console's Entities list |
| Game Data Files | entity_definitions_path reads an FGD or several |
| Prefab Factory | `place_prefab`, `quick_save_prefab` |
| Linked Groups | `quick_save_linked_prefab`, `push_to_source`, `select_linked_copies`, `propagate_prefab` |

## Visibility and layers

| Tool | HammerForge |
|---|---|
| Visgroups | `add_to_visgroup`, `new_visgroup` |
| Layers | `add_to_visgroup`, `new_visgroup` |
| Auto Visgroups | `view_filter_world`, `view_filter_trigger`, `view_filter_brush_entity`, `view_filter_entity` |
| Isolate Layer | `isolate_visgroups` |
| Lock Layer | a visgroup's lock |
| Cordon | cordons, which bake a part of the level |
| Hide Nodraw | `view_filter_hidden_faces` |

## Problems and compiling

| Tool | HammerForge |
|---|---|
| Check for Problems | `validate_level` |
| Issue Browser | `validate_level` |
| Run Map | `quick_play` |
| Compile Map | `quick_bake` |
| Launch Engine | `quick_play` |
| Load Pointfile | Not planned: a bake is no BSP compile, so there is no leak to trace |
| Load Portal File | Not planned: a bake runs no vis compile |
| Map Properties | Not yet |

## View

| Tool | HammerForge |
|---|---|
| Top, Front and Side Views | Godot's own split views, each set to Top, Front or Right |
| Camera Tool | Godot's own editor camera |
| Center View on Selection | Godot's own focus key |
| Grid Size Up | `grid_increase` |
| Grid Size Down | `grid_decrease` |
| Toggle Grid | `toggle_grid` |
| Measure | `measure` |
| Texture X-ray | `toggle_face_xray` |

## Files

| Tool | HammerForge |
|---|---|
| Open and Save Map | the .hflevel and the scene, saved with Godot's own Save |
| Export Map | the File section's Export .map |
| Import Map | the File section's Import .map |
| Export to OBJ | the File section's Export .glb |
| Autosave | the level's autosave |
| Game Configuration | Not planned: the Godot project is the game |

## Not covered yet

- Select by Line Number (Selection)
- Ignore Groups (Selection)
- Overlay Tool (Texturing)
- Paint Displacement Alpha (Texturing)
- Map Properties (Problems and compiling)
