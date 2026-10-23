# What each read costs

Replies cost context: a long one leaves less room for the rest of the job. These
were measured on HammerForge's reference map, a level of 119 brushes, 15
materials, entities and wires, with each read at its defaults unless the row
says otherwise. `tests/test_mcp_reply_costs.gd` measures them again on every CI
run and fails when one drifts by more than a quarter.

| Read | KB | What to do instead |
|---|---|---|
| `hf_get_status` | 0.8 | Nothing: call it first and often |
| `hf_get_brushes` | 179 | Pass a `filter`, `brush_ids`, `bounds` or `include_faces` false; `count_only` for "are there any?" |
| `hf_get_brushes, include_faces false` | 38 | Layout only: ids, sizes, positions, bounds |
| `hf_get_entities` | 1.5 | Grows with the entities and their wires |
| `hf_list_commands` | 37 | Once a session; the list does not change |
| `hf_validate` | 3.6 | Grows with what it finds: the reference map has 21 small brushes inside others |

The full brush listing is by far the largest: with faces, each brush costs about
1.5 KB, and the default limit is 200 brushes. Without faces it is a fifth of
that.

A screenshot is an image, not text. `hf_viewport_screenshot` at its default
1280 by 720 costs whatever a picture of that size costs the model reading it;
ask for a smaller `width` and `height` when a quick look will do, and frame it
with `focus` so the picture is of what you built.

`hf_measure` answers in well under a kilobyte for two items, which is why it is
the way to check a gap or a size.
