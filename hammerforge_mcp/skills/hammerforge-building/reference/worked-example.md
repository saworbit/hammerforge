# Worked example: two rooms and a doorway

Two rooms side by side, each 8 m by 6 m inside and 3 m tall, with 1 m walls, a
doorway 1 m wide and 2.2 m tall in the wall between them, and the spawn in the
west room. Built in three batches, then checked.

The MCP vibe sweep runs this page against a real editor: it sends each batch
below exactly as written and checks every number in the table at the end.

## 1. The plan

| Piece | Size | Centre | Spans |
|---|---|---|---|
| Floor | 19, 1, 8 | 0, 0.5, 0 | x -9.5 to 9.5, y 0 to 1, z -4 to 4 |
| Wall -z | 19, 3, 1 | 0, 2.5, -3.5 | z -4 to -3 |
| Wall +z | 19, 3, 1 | 0, 2.5, 3.5 | z 3 to 4 |
| Wall -x | 1, 3, 6 | -9, 2.5, 0 | x -9.5 to -8.5 |
| Wall +x | 1, 3, 6 | 9, 2.5, 0 | x 8.5 to 9.5 |
| Divider | 1, 3, 6 | 0, 2.5, 0 | x -0.5 to 0.5 |
| Doorway (cut) | 2, 2.2, 1 | 0, 2.1, 0 | x -1 to 1, y 1 to 3.2 |
| Spawn | | -4.5, 1, 0 | on the floor of the west room |

The floor's top is at y = 1, so it sits above a starter floor at y = 0 rather
than in the same plane. Every wall starts at y = 1, on the floor. The doorway
reaches half a metre past both faces of the divider, so it cuts clean through.

## 2. The shell

```json
{"ops": [
  {"tool": "hf_place_brush", "params": {"name": "Floor", "size": [19, 1, 8], "position": [0, 0.5, 0], "snap": false}},
  {"tool": "hf_place_brush", "params": {"name": "Wall -z", "size": [19, 3, 1], "position": [0, 2.5, -3.5], "snap": false}},
  {"tool": "hf_place_brush", "params": {"name": "Wall +z", "size": [19, 3, 1], "position": [0, 2.5, 3.5], "snap": false}},
  {"tool": "hf_place_brush", "params": {"name": "Wall -x", "size": [1, 3, 6], "position": [-9, 2.5, 0], "snap": false}},
  {"tool": "hf_place_brush", "params": {"name": "Wall +x", "size": [1, 3, 6], "position": [9, 2.5, 0], "snap": false}}
]}
```

## 3. The wall between, and its doorway

```json
{"ops": [
  {"tool": "hf_place_brush", "params": {"name": "Divider", "size": [1, 3, 6], "position": [0, 2.5, 0], "snap": false}},
  {"tool": "hf_place_brush", "params": {"name": "Doorway", "size": [2, 2.2, 1], "position": [0, 2.1, 0], "operation": "subtract", "snap": false}}
]}
```

## 4. The spawn and a light

```json
{"ops": [
  {"tool": "hf_set_spawn", "params": {"position": [-4.5, 1, 0]}},
  {"tool": "hf_place_entity", "params": {"entity_class": "light_point", "position": [4.5, 3, 0]}}
]}
```

## 5. The checks

`hf_get_status` counts six brushes and one pending cut more than before the
first batch: the doorway waits as a cut. Then
`hf_measure` each row, naming the brushes by the `brush_id` the batches answered
with:

| Check | Items | Field | Gives |
|---|---|---|---|
| The -z wall stands on the floor | Floor, Wall -z | gap | 0 |
| The west wall stands on the floor | Floor, Wall -x | gap | 0 |
| The west room is 8 m across | Wall -x, Divider | gap | 8 |
| The east room is 8 m across | Divider, Wall +x | gap | 8 |
| The doorway cuts through the divider | Doorway, Divider | gap | -1.5 |
| The doorway is 2.2 m tall | Doorway | size y | 2.2 |
| The spawn stands on the floor | Floor, [-4.5, 1, 0] | gap | 0 |

The doorway's gap is how far it would have to move to clear the divider: 1.5 m
along x, the half widths of the two added together. A positive gap there would
mean it misses the wall.

`hf_validate` should report no errors. Last, take an `hf_viewport_screenshot`
with focus bounds `{"min": [-9.5, 0, -4], "max": [9.5, 4, 4]}`. The doorway
shows as a see-through cut in the divider until `hf_bake` applies it.
