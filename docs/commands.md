---
title: Commands
description: "Every HammerForge command with its default key, what it needs, whether the palette lists it and, for the Agent Bridge, its parameters."
---

# Commands

Every command a HammerForge surface can run, from `HFCommandRegistry`. A key is
the default; the shortcut dialog (**?** on the toolbar) changes it. **Needs** is
what the selection must hold for the palette, a menu or a key to run it.

This page is written by `tools/gen_command_reference.gd`. Do not edit it by
hand: change the registry and run `godot --headless -s res://tools/gen_command_reference.gd --path .`.

## Workflow

| Command | Key | Needs | Palette | What it does |
|---|---|---|---|---|
| Toggle Add / Cut (`toggle_operation`) | Q | - | yes | Switch the next brush you draw between Add and Cut. |
| Toggle Paint Mode (`toggle_paint_mode`) | Shift+P | - | yes | Turn floor Paint mode on or off. |
| Quick Play (`quick_play`) | Ctrl+Enter | a level | yes | Bake the level and run it to test. |
| Validate Level (`validate_level`) | Ctrl+Shift+Enter | a level | yes | Check the level for problems and list them. |
| Repeat Last Command (`repeat_last_command`) | none | a level | yes | Run the last command again on the current selection, with the same settings. |
| Cycle I/O Wires (`cycle_io_wires`) | none | - | yes | Step the I/O wires through none, all, the selection's chain and its own. |

## Tools

| Command | Key | Needs | Palette | What it does |
|---|---|---|---|---|
| Draw (`tool_draw`) | D | - | yes | Switch to Draw, which makes brushes with two clicks. |
| Select (`tool_select`) | S | - | yes | Switch to Select, which picks brushes and entities. |
| Extrude Up (`tool_extrude_up`) | U | - | yes | Switch to Extrude Up: drag a face to grow a brush out of it. |
| Extrude Up (alt) (`tool_extrude`) | E | - | yes | Switch to Extrude Up, outside Paint and Vertex modes. |
| Extrude Down (`tool_extrude_down`) | J | - | yes | Switch to Extrude Down: drag a face to push a cut into it. |
| Extrude Down (alt) (`tool_extrude_down_alt`) | Shift+E | - | yes | Switch to Extrude Down, outside Paint and Vertex modes. |
| Clip Tool (`tool_clip`) | C | - | yes | Start the Clip tool, which cuts the selected brushes along a plane you place. |
| Polygon Tool (`tool_polygon`) | P | - | yes | Start the Polygon tool: click an outline on the ground, then drag its height. |
| Path Tool (`tool_path`) | ; | - | yes | Start the Path tool, which builds a corridor of brushes along the points you click. |
| Hull Tool (`tool_hull`) | none | - | yes | Start the Hull tool: click points, or a face's corners, and Enter makes one brush around them. |
| Shear Tool (`tool_shear`) | none | - | yes | Start the Shear tool: drag a handle on a side of the selection's box to lean everything between. |
| Decal Tool (`tool_decal`) | N | - | yes | Start the Decal tool, which places a decal on the surface you click. |
| Repeat Last Brush (`repeat_brush`) | Shift+D | a level | yes | Arm a stamp of the brush the last Draw made; each click places one. |
| Place Entity Here (`place_entity_here`) | none | a level | no | Place an entity on the surface under the cursor, standing on it. |
| Apply Last Texture (`apply_last_texture`) | Shift+T | 1 brush or faces, a level | yes | Give the selection the material the Texture Picker last sampled. |
| Apply Picked Look (`apply_picked_look`) | Alt+T | a level | yes | Give the selected faces the picked face's material and alignment. |
| Replace Material... (`replace_material`) | none | a level | yes | Swap one material for another on every face that wears it. |
| Apply Favorite 1 (`apply_favorite_1`) | Alt+1 | 1 brush or faces, a level | yes | Give the selected faces or brushes favorite 1 from the context toolbar. |
| Apply Favorite 2 (`apply_favorite_2`) | Alt+2 | 1 brush or faces, a level | yes | Give the selected faces or brushes favorite 2 from the context toolbar. |
| Apply Favorite 3 (`apply_favorite_3`) | Alt+3 | 1 brush or faces, a level | yes | Give the selected faces or brushes favorite 3 from the context toolbar. |
| Apply Favorite 4 (`apply_favorite_4`) | Alt+4 | 1 brush or faces, a level | yes | Give the selected faces or brushes favorite 4 from the context toolbar. |
| Apply Favorite 5 (`apply_favorite_5`) | Alt+5 | 1 brush or faces, a level | yes | Give the selected faces or brushes favorite 5 from the context toolbar. |
| Apply Favorite 6 (`apply_favorite_6`) | Alt+6 | 1 brush or faces, a level | yes | Give the selected faces or brushes favorite 6 from the context toolbar. |
| Apply Favorite 7 (`apply_favorite_7`) | Alt+7 | 1 brush or faces, a level | yes | Give the selected faces or brushes favorite 7 from the context toolbar. |
| Apply Favorite 8 (`apply_favorite_8`) | Alt+8 | 1 brush or faces, a level | yes | Give the selected faces or brushes favorite 8 from the context toolbar. |
| Apply Favorite 9 (`apply_favorite_9`) | Alt+9 | 1 brush or faces, a level | yes | Give the selected faces or brushes favorite 9 from the context toolbar. |
| Texture Gizmo (`texture_gizmo`) | none | - | no | Show or hide the texture gizmo, which slides, stretches and turns a face's texture by dragging. |
| Vertex Edit (`vertex_edit`) | V | 1 brush, a level | yes | Turn Vertex mode on or off, to move the selected brushes' corners and edges. |
| Edge Mode (`vertex_edge_mode`) | E | a level | yes | In Vertex mode, switch between picking corners and edges. |
| Merge Vertices (`vertex_merge`) | Ctrl+W | 1 brush, a level | yes | Merge the selected vertices into one at their middle. |
| Split Edge (`vertex_split_edge`) | Ctrl+E | 1 brush, a level | yes | Split the selected edge at its middle. |
| Snap Vertices to Grid (`vertex_snap_to_grid`) | Ctrl+B | 1 brush, a level | yes | Move the selected vertices to their nearest grid points. |
| Scale Vertices... (`vertex_scale`) | none | 1 brush, a level | yes | Scale the selected vertices by typed factors, about their middle or the picked pivot. |
| Texture Picker (`texture_picker`) | T | a level | yes | Sample a face's material and its whole look, for Apply Last Texture and Apply Picked Look. |
| Measure (`measure`) | M | - | yes | Start the Measure tool, which draws rulers between points. |
| Context Menu (`context_menu`) | Space | a level | yes | Open the context menu at the cursor. |
| Radial Menu (`radial_menu`) | &#96; | - | yes | Open the radial menu, when Power-user overlays are on. |
| Operation Replay Timeline (`toggle_operation_replay`) | Ctrl+Shift+T | - | yes | Show or hide the operation replay timeline, when Power-user overlays are on. |

## Editing

| Command | Key | Needs | Palette | What it does |
|---|---|---|---|---|
| Extrude Up (`extrude_up`) | none | - | no | Switch to Extrude Up: drag a face to grow a brush out of it. |
| Extrude Down (`extrude_down`) | none | - | no | Switch to Extrude Down: drag a face to push a cut into it. |
| Hollow (`hollow`) | Ctrl+H | 1 brush, a level | yes | Shell the selected brush into walls of the set thickness, after a preview. |
| Clip (`clip`) | Shift+X | 1 brush, a level | yes | Split the selected brush in two across its middle, after a preview. |
| Clip to Face Plane (`clip_to_face`) | Shift+Alt+X | a level | yes | Cut the selected brushes along the plane of the face picked in Face Select. |
| Create Structure (`create_arch`) | Ctrl+Shift+A | a level | yes | Open the structure builder: stairs, arches, domes and the rest. |
| Update Structure (`update_structure`) | none | a level | no | Rebuild the selected structure from the settings in its section. |
| Detach Structure (`detach_structure`) | none | a level | no | Make the selected structure's pieces plain brushes, so an Update no longer rebuilds them. |
| Run Trim Along Faces (`run_trim_along_faces`) | Shift+Alt+T | a level | yes | Run a skirting or cornice along the wall faces picked in Face Select. |
| Re-pick Trim Run (`repick_trim_run`) | none | a level | no | Move the selected trim run onto the wall faces picked in Face Select. |
| Carve (`carve`) | Ctrl+Shift+R | 1 brush, a level | yes | Cut the selected brush out of every brush it overlaps, after a preview. |
| Merge Brushes (`merge`) | Ctrl+Shift+M | 2 brushes, a level | yes | Join the selected brushes into one brush. |
| Hull of Selection (`hull`) | none | 2 brushes, a level | yes | Replace the selected brushes with one brush around them all, touching or not. |
| Intersect (`intersect`) | Ctrl+Shift+I | 2 brushes, a level | yes | Keep only the volume the selected brushes share. |
| Convert to Brushes (`convert_to_brushes`) | none | no mix of HammerForge and Godot nodes, a level | no | Make the selected convex mesh or CSG node a brush where it stands. |
| Duplicate (`duplicate`) | Ctrl+D | 1 item, a level | yes | Copy the selected brushes and entities in place. |
| Copy (`copy`) | Ctrl+C | 1 item, a level | yes | Put the selection on the clipboard. |
| Paste (`paste`) | Ctrl+V | nothing, a level | yes | Place what is on the clipboard where it was copied from. |
| Delete (`delete`) | Del | 1 item, a level | yes | Delete the selected brushes and entities. |
| Group (`group`) | Ctrl+G | 2 items, a level | yes | Group the selected brushes, so a click picks them all. |
| Ungroup (`ungroup`) | Ctrl+U | 1 item, a level | yes | Take the selected brushes out of their group. |
| Make Brush Entity (`make_brush_entity`) | none | 1 brush, a level | no | Tie the selected brushes to a brush entity class, such as a trigger or a door. |
| Back to World (`back_to_world`) | none | 1 brush, a level | no | Untie the selected brushes from their brush entity, so they are plain world brushes. |
| Add to Visgroup (`add_to_visgroup`) | none | 1 item, a level | no | Add the selected brushes and entities to a visgroup. |
| New Visgroup (`new_visgroup`) | none | 1 item, a level | no | Make a new visgroup holding the selected brushes and entities. |
| Move to Floor (`move_to_floor`) | Ctrl+Shift+F | 1 brush, a level | yes | Drop the selection onto the nearest surface below it. |
| Move to Ceiling (`move_to_ceiling`) | Ctrl+Shift+C | 1 brush, a level | yes | Lift the selection to the nearest surface above it. |
| Shape Box (`shape_box`) | none | - | no | Draw boxes from now on. |
| Shape Cylinder (`shape_cylinder`) | none | - | no | Draw cylinders from now on. |
| Shape Sphere (`shape_sphere`) | none | - | no | Draw spheres from now on. |
| Shape Cone (`shape_cone`) | none | - | no | Draw cones from now on. |
| Justify Fit (`justify_fit`) | none | 1 brush or faces | yes | Stretch the texture to fit the selected faces. |
| Justify Center (`justify_center`) | none | 1 brush or faces | no | Centre the texture on the selected faces. |
| Justify Left (`justify_left`) | none | 1 brush or faces | no | Line the texture's left edge up with the faces' left edge. |
| Justify Right (`justify_right`) | none | 1 brush or faces | no | Line the texture's right edge up with the faces' right edge. |
| Justify Top (`justify_top`) | none | 1 brush or faces | no | Line the texture's top edge up with the faces' top edge. |
| Justify Bottom (`justify_bottom`) | none | 1 brush or faces | no | Line the texture's bottom edge up with the faces' bottom edge. |
| Justify Fit U (`justify_fit_u`) | none | 1 brush or faces | yes | Stretch the texture across the selected faces' width only. |
| Justify Fit V (`justify_fit_v`) | none | 1 brush or faces | yes | Stretch the texture across the selected faces' height only. |
| UV Flip U (`uv_flip_u`) | none | 1 brush or faces | yes | Flip the texture left to right on the selected faces. |
| UV Flip V (`uv_flip_v`) | none | 1 brush or faces | yes | Flip the texture top to bottom on the selected faces. |
| Align Texture to Edge (`align_texture_to_edge`) | none | 1 brush or faces | yes | Turn the texture to run along an edge of each selected face, the next edge each time. |
| Fit Texture Repeats (`fit_texture_repeats`) | none | 1 brush or faces | yes | Show the Paint tab's count of whole repeats across the selected faces. |
| Fit Trim Strip (`fit_texture_strip`) | none | 1 brush or faces | yes | Fit one strip of a trim sheet, as the Paint tab's Strip sets it, to the selected faces. |
| UV Rotate 90 (`uv_rotate_90`) | none | 1 brush or faces | yes | Turn the texture a quarter turn on the selected faces. |
| Align to Face (`uv_align_face`) | none | 1 brush or faces | yes | Lay the texture along each selected face's own plane. |
| Align to World (`uv_align_world`) | none | 1 brush or faces | yes | Lay the texture on the world's axes, so neighbouring faces line up. |
| Link Faces (`uv_link`) | none | 1 brush or faces | yes | Make the selected faces one surface that shares one texture mapping. |
| Unlink Faces (`uv_unlink`) | none | 1 brush or faces | yes | Give the selected faces their own texture mapping again. |
| Wrap Texture (`uv_wrap`) | none | a level | yes | Carry the selected face's texture over an edge onto the next face you click. |
| Apply to Brush (`apply_to_brush`) | none | 1 brush or faces | yes | Give every face of the selected brushes the material selected in the browser. |
| Entity I/O (`entity_io`) | none | 1 item | no | Open the Entities tab, where outputs and their targets are wired. |
| Entity Props (`entity_props`) | none | 1 item | no | Open the Entities tab, where the selected entity's properties are edited. |
| Highlight Connected (`highlight_connected`) | none | 1 item | no | Pulse every entity wired to the selected one. |
| Vertex Submode (`vertex_submode`) | none | 1 brush | no | In Vertex mode, pick corners. |
| Edge Submode (`edge_submode`) | none | 1 brush | no | In Vertex mode, pick edges. |
| Vertex Split (`vertex_split`) | none | 1 brush | no | Split the selected edge at its middle. |
| Vertex Clip Convex (`vertex_clip_convex`) | none | 1 brush, a level | no | Rebuild each brush with vertices selected from its convex hull, when it is no longer convex. |
| Vertex Exit (`vertex_exit`) | none | - | no | Leave Vertex mode. |
| Save Selection as Prefab (`quick_save_prefab`) | Ctrl+Shift+P | 1 item | yes | Save the selected brushes and entities as a prefab. |
| Quick Save Linked Prefab (`quick_save_linked_prefab`) | none | 1 item | no | Save the selection as a prefab and make it a linked copy of the file. |
| Cycle Prefab Variant (`cycle_variant`) | Ctrl+Shift+V | 1 item | yes | Switch the selected prefab copy to its next variant. |
| Push to Source (`push_to_source`) | none | 1 item | no | Write the selected linked copy's changes back to its prefab file. |
| Unlink Prefab Copy (`unlink_prefab_copy`) | none | 1 item, a level | yes | Cut the selected copy's link to its prefab, keeping what it is. |
| Discard Prefab Changes (`discard_prefab_changes`) | none | 1 item, a level | yes | Rebuild the selected linked copy from its prefab, dropping its changes. |
| Propagate Prefab (`propagate_prefab`) | none | 1 item | no | Bring every linked copy of the selected prefab up to date with its file. |
| Place Prefab (`place_prefab`) | none | a level | no | Place the prefab chosen in the library at the cursor. |
| Surface Paint (`surface_paint`) | none | - | no | Turn floor Paint mode on. |
| Grid Decrease (`grid_decrease`) | [ | a level | yes | Halve the grid step. |
| Grid Increase (`grid_increase`) | ] | a level | yes | Double the grid step. |
| Grid Up (`grid_up`) | Alt+PgUp | a level | yes | Raise the drawing plane one grid step. |
| Grid Down (`grid_down`) | Alt+PgDn | a level | yes | Lower the drawing plane one grid step. |
| Reset Grid (`grid_reset`) | Alt+Home | a level | yes | Put the drawing plane back at the level's origin, flat. |
| Align Grid to Selection (`grid_align`) | Alt+End | a level | yes | Move the drawing plane to the selected face, vertices or brush top. |
| Toggle Grid (`toggle_grid`) | none | - | no | Show or hide the grid. |
| Quick Bake (`quick_bake`) | none | - | no | Bake the level. |
| Undo (`undo`) | none | - | no | Take back the last change. |
| Redo (`redo`) | none | - | no | Put back the last change undone. |
| Set Grid Snap (`set_grid_snap`) | none | - | no | Set the grid step to a value. |
| Next Pick: Vertex Only (`snap_next_vertex`) | none | a level | yes | The next click snaps only to a vertex, whatever snaps are on, then they all return. |
| Next Pick: Midpoint Only (`snap_next_midpoint`) | none | a level | yes | The next click snaps only to the middle of an edge, then every snap that was on returns. |
| Next Pick: Centre Only (`snap_next_centre`) | none | a level | yes | The next click snaps only to a brush's centre, then every snap that was on returns. |
| Next Pick: Perpendicular Only (`snap_next_perpendicular`) | none | a level | yes | The next click snaps only to the foot of a perpendicular on an edge, then every snap returns. |
| Next Pick: Grid Only (`snap_next_grid`) | none | a level | yes | The next click snaps only to the grid, even with Grid off, then every snap that was on returns. |
| Cancel Drag (`cancel_drag`) | none | - | no | Stop the drag in progress and clear any typed number. |
| Apply Pending Cuts (`apply_pending_cuts`) | none | - | no | Apply the cuts waiting in Pending Cuts to the brushes they overlap. |
| Commit Cuts (`commit_cuts`) | none | - | no | Apply the pending cuts and bake. |
| Clear Pending Cuts (`clear_pending_cuts`) | none | - | no | Delete the cuts waiting in Pending Cuts. |
| Bake Preview Toggle (`bake_preview_toggle`) | none | - | no | Show the bake as a wireframe over the brushes, or stop showing it. |
| Apply Context Material (`apply_context_material`) | none | 1 brush or faces | no | Give the selection the material clicked on the context toolbar. |

## Transform

| Command | Key | Needs | Palette | What it does |
|---|---|---|---|---|
| Rotate CCW (`rotate_ccw`) | R | a level | yes | Turn the selection a step counterclockwise. |
| Rotate CW (`rotate_cw`) | Shift+R | a level | yes | Turn the selection a step clockwise. |
| Flip Selection (`flip_selection`) | Shift+M | a level | yes | Mirror the selection in place across an axis. |
| Shear (`shear_selection`) | none | 1 item, a level | yes | Lean the selection: one side moves along an axis and the opposite side stays put. |
| Mirror Copy (`mirror_copy`) | Alt+M | 1 item, a level | yes | Keep the selection and add copies mirrored across the ticked axes. |
| Offset (`offset_selection`) | Alt+G | 1 item or faces, a level | yes | Move the selection, its vertices or its faces by a typed X, Y and Z. |
| Pick Pivot (`pick_pivot`) | Alt+P | a level | yes | Click a brush vertex, edge or face to turn and flip about. |
| Clear Pivot (`clear_pivot`) | Shift+Alt+P | a level | yes | Go back to turning about the selection's centre. |
| Reset Rotation (`reset_rotation`) | Alt+R | a level | yes | Turn the selection back to no rotation. |
| Apply Rotation and Scale (`apply_rotation_scale`) | none | 1 brush, a level | yes | Fold the selected brushes' rotation and scale into their shape, so nothing moves. |
| Snap to Grid (`snap_to_grid`) | Ctrl+B | 1 item, a level | yes | Put each selected brush's corner, or entity's origin, on the grid. |

## Selection

| Command | Key | Needs | Palette | What it does |
|---|---|---|---|---|
| Select Linked Faces (`uv_select_group`) | none | - | yes | Select every face linked with the selected face. |
| Select All (`select_all`) | A | a level | yes | Select every brush and entity. |
| Invert Selection (`invert_selection`) | none | a level | yes | Select what is not selected, and drop what is. |
| Select Inside (`select_inside`) | none | 1 brush, a level | yes | Select every brush wholly inside the selected brush, and every entity in it. |
| Select Partly Inside (`select_partly_inside`) | none | 1 brush, a level | yes | Select every brush at least partly inside the selected brush. |
| Select Touching (`select_touching`) | none | 1 brush, a level | yes | Select every brush that touches or overlaps the selected brush. |
| Select Column (`select_column`) | none | 1 brush, a level | yes | Select Inside, with the selected brush's footprint running from the bottom of the level to the top. |
| Hide Selection (`hide_selection`) | Alt+H | 1 item, a level | yes | Hide the selection until Show Hidden, without a visgroup. |
| Show Hidden (`show_hidden`) | Shift+Alt+H | a level | yes | Show what Hide Selection and an isolate hid. |
| Isolate Selection (`isolate_selection`) | none | 1 item, a level | yes | Show only the selection, whatever visgroups it is in. |
| Isolate Visgroups (`isolate_visgroups`) | none | 1 item, a level | yes | Show only the visgroups the selection is in. |
| End Isolate (`end_isolate`) | none | a level | yes | Show what an isolate hid. |
| Previous Visibility (`previous_visibility`) | none | a level | yes | Go back to what was shown before the last hide or isolate. |
| Deselect All (`deselect_all`) | Shift+A | a level | yes | Select nothing: brushes, entities and faces. |
| Select Similar (`select_similar`) | Shift+S | 1 item or faces, a level | yes | Select the faces, brushes or entities like the ones selected, on what Selection Filters ticks. |
| Selection Filters (`selection_filter`) | Alt+F | no mix of HammerForge and Godot nodes | yes | Open the selection filters, which pick by kind, material and more. |
| Quick Select (`quick_select`) | none | no mix of HammerForge and Godot nodes, a level | yes | Select brushes or entities by a typed rule, such as class is light_point and energy > 2. |
| Grow Selection (`grow_selection`) | Ctrl+] | 1 item or faces, a level | yes | Add the faces next to the selected faces, or the brushes touching the selected brushes. |
| Shrink Selection (`shrink_selection`) | Ctrl+[ | 1 item or faces, a level | yes | Drop the selected faces or brushes on the edge of the selection. |
| Toggle Face X-ray (`toggle_face_xray`) | Alt+X | - | yes | Let the face marquee take covered and back faces. |
| Show Selection Size (`toggle_selection_size`) | Alt+D | - | yes | Label the selection's width, depth and height in the viewport. |
| Select Linked Copies (`select_linked_copies`) | none | 1 item, a level | yes | Select every copy linked to the selected copy's prefab. |

## Paint

| Command | Key | Needs | Palette | What it does |
|---|---|---|---|---|
| Show Material in Browser (`show_material_in_browser`) | none | 1 brush or faces, a level | no | Select the picked face's material in the material browser. |
| Paint Brush (`paint_bucket`) | B | - | yes | Paint floor cells. |
| Erase (`paint_erase`) | E | - | yes | Erase floor cells. |
| Ramp / Rect (`paint_ramp`) | R | - | yes | Paint a rectangle of floor cells. |
| Line (`paint_line`) | L | - | yes | Paint a line of floor cells. |
| Bucket Fill (`paint_fill`) | K | - | yes | Fill a connected area of floor cells. |
| Blend (`paint_blend`) | N | - | yes | Paint the blend between ground materials. |
| Raise Painted Walls (`paint_raise`) | Y | a level | yes | Raise walls round the last painted footprint. |
| Toggle Paint Mirror X (`paint_mirror_x`) | X | a level | yes | Mirror painting across the grid's X origin. |
| Toggle Paint Mirror Z (`paint_mirror_z`) | Z | a level | yes | Mirror painting across the grid's Z origin. |
| Stamp Painted Room (`paint_room`) | H | a level | yes | Repeat the last rectangle as a floor with walls round it. |
| Confirm Paint Connector (`paint_confirm_connector`) | Enter | a level | yes | Keep the ramp or stair ghost shown between painted layers. |

## Axis Lock

| Command | Key | Needs | Palette | What it does |
|---|---|---|---|---|
| Lock X (`axis_x`) | X | a level | yes | Hold the next drag to the X axis. |
| Lock Y (`axis_y`) | Y | a level | yes | Hold the next drag to the Y axis. |
| Lock Z (`axis_z`) | Z | a level | yes | Hold the next drag to the Z axis. |
| Draw on Face (`toggle_draw_on_face`) | L | - | yes | Build a draw on the plane of the face it starts on. |

## Agent Bridge

These commands an agent may run over the bridge with `hf_run_command`, on the
brushes and entities it names, never on the selection. `hf_list_commands` gives
the same parameters as JSON Schema.

### Hollow (`hollow`)

Shell one brush into walls: each face becomes a wall of the given thickness, inward from the face, so a box gives six walls and a cylinder a pipe. The brush is replaced by the walls (made), and the shell stays editable as a hollow. Brushes with more than 128 distinct faces (spheres, capsules, tori) are refused.

| Param | Type | Range | Default | Description |
|---|---|---|---|---|
| `thickness` | float | 0.05 to 128 | 0.25 | Wall thickness in metres |

### Clip (`clip`)

Split one brush in two along a plane across an axis. position is where the plane crosses that axis in world space, snapped to the grid, and must fall inside the brush; without it the brush is cut through its middle. The brush is replaced by the two pieces (made); split_position says where the cut went.

| Param | Type | Range | Default | Description |
|---|---|---|---|---|
| `axis` | axis | - | y | The axis the cut crosses: x, y or z |
| `position` | float | - | - | World coordinate along the axis; the brush's middle if absent |

### Clip to Face Plane (`clip_to_face`)

Cut brushes along the plane of one face of another brush, the way Clip to Face Plane does: an angled cut taken from an existing surface. Each brush the plane passes through is replaced by its pieces; those it misses are listed in skipped. Refused when it passes through none of them.

| Param | Type | Range | Default | Description |
|---|---|---|---|---|
| `plane_brush_id` (required) | string | - | - | The brush whose face gives the plane |
| `plane_face` (required) | face | - | - | That face: an index, a world side such as '+y', or {normal: [x, y, z]} |

### Create Structure (`create_arch`)

Build a structure from a generator: an arch, a straight flight of stairs, a spiral stair, a dome, a ring or a door frame, one brush per piece, kept as a live structure. A door frame with cut_opening on also holds the cut for its opening, a pending cut until applied. type picks the generator; settings sets its fields by key (see settings_by_type for each type's keys, ranges and defaults; anything not given keeps its default). position is where it stands and rotation_degrees turns it, Euler XYZ. The pieces come back in made, and generator_id names the structure.

| Param | Type | Range | Default | Description |
|---|---|---|---|---|
| `type` (required) | enum | - | - | arch, stairs, spiral_stairs, dome, ring or door_frame |
| `settings` | object | - | - | The type's settings by key; see settings_by_type |
| `position` (required) | vec3 | - | - | Where the structure stands, [x, y, z] |
| `rotation_degrees` | vec3 | - | - | Euler XYZ degrees; none if absent |

### Update Structure (`update_structure`)

Rebuild a structure in place from new settings. generator_id names it, as create_arch answers it and hf_get_brushes gives it on each piece. settings sets fields by key, as create_arch takes them for the structure's type (see settings_by_type, which has a Trim Run's keys as well); anything not given keeps the structure's current value. A structure moved or turned as a whole rebuilds where it stands. Each piece keeps its paint, name, brush entity and visgroups where the new pieces line up with the old. Every piece gets a new brush_id: made lists them and removed the old ones. Settings the structure already has, with no piece edited, moved on its own or deleted, rebuild nothing: every piece keeps its brush_id and no_change is true. appearance_dropped lists the old pieces whose paint these settings could not keep, and edits_replaced the pieces edited or deleted by hand that the rebuild put back to the settings' shape.

| Param | Type | Range | Default | Description |
|---|---|---|---|---|
| `generator_id` (required) | string | - | - | The structure, as create_arch or hf_get_brushes gives it |
| `settings` | object | - | - | The fields to change, by key; see settings_by_type |

### Detach Structure (`detach_structure`)

Make a structure's pieces ordinary brushes, left where they are with everything on them. update_structure can no longer rebuild them, so hand edits are safe from it. generator_id names the structure. detached lists the pieces.

| Param | Type | Range | Default | Description |
|---|---|---|---|---|
| `generator_id` (required) | string | - | - | The structure, as create_arch or hf_get_brushes gives it |

### Carve (`carve`)

Cut each carver's shape out of every brush it overlaps. The brushes cut are replaced by their pieces, and the carver is used up: it is removed too. A carver that overlaps nothing is listed in skipped; if none overlaps anything, it is refused.

No parameters.

### Merge Brushes (`merge`)

Merge two or more brushes into one: the convex solid they make together. Refused when that solid would not be convex (an L shape, two separate blocks), or when it mixes solid brushes and cuts. The sources are replaced by one brush, given as brush.

No parameters.

### Hull of Selection (`hull`)

Replace two or more brushes with one brush, the convex hull of all their corners, whether they touch or not. It is turned as the first brush in brush_ids is and keeps its operation, visgroups, group and brush entity. A face on an old face's plane keeps that face's look; a new face takes the Active Material. Refused when the brushes mix solid brushes and cuts or are not all one entity.

No parameters.

### Intersect (`intersect`)

Keep only the volume two or more brushes share. The first brush in brush_ids is cut down by the planes of each of the others, and what is left, one convex brush given as brush, replaces them all. It keeps the first brush's operation, visgroups, group and brush entity; each face keeps the look of the brush whose plane it lies on. Refused when the brushes share no volume, mix solid brushes and cuts, or are not all one entity.

No parameters.

### Reset Rotation (`reset_rotation`)

Turn each brush back to no rotation about its own centre, keeping its position and size.

No parameters.

### Move to Floor (`move_to_floor`)

Move each brush straight down until its bottom rests on the first surface below it: the floor, a brush, or baked collision. Its x and z stay; the new height snaps to the grid.

No parameters.

### Move to Ceiling (`move_to_ceiling`)

Move each brush straight up until its top meets the first surface above it. Its x and z stay; the new height snaps to the grid.

No parameters.

### Snap to Grid (`snap_to_grid`)

Move each brush the least distance that puts the lowest corner of its world bounds on a point of the level's grid: a whole number of grid_snap steps from the origin on each axis. Size and rotation stay, so a brush sized in whole steps ends with every corner on the grid. A brush already there is left alone. Refused when grid_snap is 0.

No parameters.

### Replace Material... (`replace_material`)

Give every face that wears the material from the material to, what Replace Material does, as one step: across the level, on the brushes brush_ids names when it names any, and on shown brushes alone with scope shown. Each face keeps its UV scale, offset and rotation unless reset_uv is true. from and to are ids or names that hf_get_materials lists. The answer gives faces, how many changed, and brushes, each changed brush's brush_id with its face indices; those faces become the face selection.

| Param | Type | Range | Default | Description |
|---|---|---|---|---|
| `from` (required) | string | - | - | The material to replace, by id or name |
| `to` (required) | string | - | - | The material to put in its place, by id or name |
| `scope` | enum: level, shown | - | level | level, or shown for brushes that are not hidden |
| `reset_uv` | bool | - | false | Put each face's UV scale, offset and rotation back to none |

### Cycle Prefab Variant (`cycle_variant`)

Switch a placed prefab to its next variant, rebuilding its pieces. Name any one piece of it, a brush or an entity; hf_get_brushes and hf_get_entities give each piece's prefab. Refused for a prefab with one variant.

No parameters.

### Propagate Prefab (`propagate_prefab`)

Rebuild every linked copy of a prefab from its saved file, as Propagate Prefab does. Name any one piece of a copy of it, a brush or an entity. Refused when no copy of that prefab is linked.

No parameters.

### Place Prefab (`place_prefab`)

Place a prefab from the project's prefab library. Its pieces come in as new brushes and entities with fresh names and ties, as a drop from the library makes them, recorded as a copy that cycle_variant and propagate_prefab can change. prefab names it: prefabs lists the library, each one's name, variants, tags and how many brushes and entities it holds. position is where its centre goes, exactly; rotation_degrees turns it about that centre, Euler XYZ. variant picks one of its variants. linked makes the copy follow its file when the file changes and is propagated. The answer gives instance_id, the brushes made and entities_made.

| Param | Type | Range | Default | Description |
|---|---|---|---|---|
| `prefab` (required) | string | - | - | The library prefab's name; see prefabs |
| `position` (required) | vec3 | - | - | Where its centre goes, [x, y, z] |
| `rotation_degrees` | vec3 | - | - | Euler XYZ degrees about its centre; none if absent |
| `variant` | string | - | - | One of its variants; its base if absent |
| `linked` | bool | - | false | Whether the copy follows its file when propagated |

### Ramp / Rect (`paint_ramp`)

Paint or erase a rectangle of floor cells on a paint layer, what the Rect tool does with a drag. A cell is [x, z] on the layer's grid, one grid step square, the grid's second axis along world Z. from and to are two corners, both included, in any order; to alone is from, so one cell is a rectangle of one. Filled cells get a floor and walls round the edge of the painted area, rebuilt before the answer, and the walls stand at the default height until paint_raise sets one. filled false erases the cells. material writes a cell material id on the filled cells, as the Blend tool does. layer is a layer's index or name from paint_layers; the layer the Paint tab has active if absent. The answer gives the layer used, cells, cells_changed (how many filled bits flipped), materials_changed (how many cell material ids changed), and bounds, the rectangle in world metres on the floor's top.

| Param | Type | Range | Default | Description |
|---|---|---|---|---|
| `layer` | layer | - | - | The paint layer, by index from 0 or by name; the active one if absent |
| `from` (required) | cell | - | - | One corner of the rectangle, [x, z] in cells |
| `to` | cell | - | - | The opposite corner, [x, z] in cells; from if absent |
| `filled` | bool | - | true | true paints the cells, false erases them |
| `material` | int | 0 to 255 | - | A cell material id for the filled cells, as the Blend tool writes one |

### Raise Painted Walls (`paint_raise`)

Set the wall height of the painted cells in a rectangle on a paint layer, what the Y gesture does for the last stroke: the walls round that floor are rebuilt at height metres, before the answer. Cells in the rectangle that are not painted are left alone, and a rectangle with none painted is refused; paint_ramp paints them. from and to are two corners, [x, z] in cells, both included; to alone is from. layer is an index or a name from paint_layers; the active layer if absent. The answer gives raised, the painted cells, and heights_changed, how many overrides were added or changed, including pinning cells to the default height.

| Param | Type | Range | Default | Description |
|---|---|---|---|---|
| `layer` | layer | - | - | The paint layer, by index from 0 or by name; the active one if absent |
| `from` (required) | cell | - | - | One corner of the rectangle, [x, z] in cells |
| `to` | cell | - | - | The opposite corner, [x, z] in cells; from if absent |
| `height` (required) | float | 0.25 to 256 | - | The wall height in metres |

### Stamp Painted Room (`paint_room`)

Paint a room on a paint layer: a width by depth rectangle of floor cells whose lowest corner is at, [x, z] in cells, and, when height is given, its walls raised to that many metres, in one step. What the H key does with the last rectangle's size at the hovered cell, with the size and the corner named; width and depth default to 4, the size the tool starts with. Without height the walls stand at the default height. layer is an index or a name from paint_layers; the active layer if absent. The answer gives from and to, the corners painted, cells, cells_changed, raised, and bounds, the room in world metres on the floor's top.

| Param | Type | Range | Default | Description |
|---|---|---|---|---|
| `layer` | layer | - | - | The paint layer, by index from 0 or by name; the active one if absent |
| `at` (required) | cell | - | - | The room's lowest corner, [x, z] in cells |
| `width` | int | 1 to 256 | 4 | Cells along x |
| `depth` | int | 1 to 256 | 4 | Cells along z |
| `height` | float | 0.25 to 256 | - | The wall height in metres; the default height if absent |

### Confirm Paint Connector (`paint_confirm_connector`)

Keep a ramp or stairs between two paint layers at different heights, what Enter does for the ghost a stroke proposes: where a painted cell in the rectangle on layer sits beside a painted cell of another layer, a connector is confirmed across that edge and built by the next bake, with the level's connector mode, stair height and width. from and to are two corners, [x, z] in cells, both included; to alone is from. to_layer keeps only connectors that join that layer. One already confirmed is counted in already, not added again; a rectangle that meets no other layer, or only boundaries already confirmed, is refused. The answer lists connectors, each one's from_layer, to_layer, from_cell, to_cell, type and width_cells.

| Param | Type | Range | Default | Description |
|---|---|---|---|---|
| `layer` | layer | - | - | The paint layer the cells are on, by index from 0 or by name; the active one if absent |
| `from` (required) | cell | - | - | One corner of the rectangle, [x, z] in cells |
| `to` | cell | - | - | The opposite corner, [x, z] in cells; from if absent |
| `to_layer` | layer | - | - | Only connectors to this layer, by index or name; any other layer if absent |
