---
name: hammerforge-building
description: How to build or change a HammerForge level in the Godot editor through the hf_* tools of the HammerForge MCP bridge. Plan the level as numbers, build it in a few hf_batch calls, then measure, validate and look before saying it is done. Use whenever you place, move or check brushes, entities or a spawn with these tools.
---

# Building a level with HammerForge

HammerForge builds levels out of brushes: boxes, wedges, cylinders and other
convex solids that add volume, and subtract brushes that cut it away. The bridge
lets you build one in the editor the person has open. Every change you make is
one undo step in their editor, named `MCP: ...`, so they can see it and take it
back.

## The loop

1. **Look first.** Call `hf_get_status`. It says which scene is open, whether it
   has a level, and how many brushes and entities it holds. With no level, call
   `hf_create_starter`, which makes one with a floor whose top is at y = 0.
2. **Plan as numbers.** Before calling anything that changes the level, write the
   plan as a table: each brush with its size and its centre, and each cut. Most
   mistakes are arithmetic, and a table is where you catch them. The
   [conventions](reference/conventions.md) say what the numbers mean.
3. **Build in a few batches.** Send the plan through `hf_batch`, up to 100 changes
   in one call, rather than one call a brush. A batch is one undo step, so a bad
   one is one `hf_undo` away. Group it by what you would undo together: the
   shell, then the cuts, then the details.
4. **Check what you built.** Not by reading face lists:
   - `hf_get_status` for the counts you planned;
   - `hf_measure` for the gaps and sizes that matter: a wall stands on the floor
     when their gap is 0, a doorway cuts its wall when their gap is negative;
   - `hf_validate` for what HammerForge would warn about before a bake;
   - `hf_viewport_screenshot` with `focus` set to what you built, to look.
5. **Fix it.** Undo a batch with `hf_undo`, or send another batch that corrects
   it. Then check again.

Say you are done only once the checks agree with the plan.

## What costs what

Replies are small except the full listings. On a level of a few hundred brushes,
`hf_get_brushes` with its faces is the largest reply you can ask for, and a
screenshot is next. Find before you read: a `filter` such as
`{"operation": "subtract"}` or `{"material": "brick"}`, `include_faces` false, a
`limit`, or `brush_ids` when you only need some, and `count_only` when the count
is the answer. [What each read costs](reference/costs.md) has the
measured sizes.

## When something is wrong

[Warning signs](reference/warning-signs.md) lists the answers that mean a plan
went wrong, such as a cut that misses its wall or a spawn over nothing.

## A worked example

[Two rooms and a doorway](reference/worked-example.md), built in three batches,
with the numbers each check should give at the end.
