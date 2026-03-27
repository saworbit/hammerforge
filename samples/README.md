# Sample Levels

## `hf_editor_smoke_start.tscn`
Empty 3D scene used with `res://tools/prepare_editor_smoke.gd` and
`docs/HammerForge_Editor_Smoke_Checklist.md` for repeatable editor smoke tests.

## `hf_sample_minimal.tscn`
Small scene with a floor and wall DraftBrush for quick smoke tests.

## `hf_sample_stress.tscn`
Scene that uses `hf_stress_spawner.gd` to populate a grid of brushes for performance testing.

### Stress Spawner Controls
- `grid_x`, `grid_z` control the grid size.
- `spacing` controls spacing between brushes.
- `brush_size` controls generated brush dimensions.
- Toggle `regenerate` to rebuild the grid.
