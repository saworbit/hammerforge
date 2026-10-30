# Heights per chunk (#2007)

## The defect

A paint layer kept its terrain in one image and read a cell's height at
`posmod(cell, width)`. So the ground repeated every width of the image, and a
sculpt landed once under the brush and again a width away on every side. #2017
made Generate Noise seamless, which took away the cliff along x = 0 and z = 0,
and rebuilt the far chunks a sculpt reached. The repeat itself stayed: on a
64 pixel map one Raise at cell (10, 2) also raised cell (74, 2).

## What the ground is now

A layer's height at a corner is one of two things:

- **A sculpted sample**, where a sculpt has been. Sculpts are kept per chunk, a
  `chunk_size` square of float samples for each chunk a sculpt reached, by chunk
  id beside the paint chunks. A chunk owns the corners from its own first cell
  up to the cell before the next chunk; the far corners of its last row and
  column belong to the next one.
- **The base**, everywhere else. The base is what the layer was given:
  - nothing, which is flat;
  - a noise field, from Generate Noise. It is the noise itself, sampled at each
    corner, `noise(x, y) * 0.5 + 0.5`, which is what `FastNoiseLite.get_image()`
    gives a pixel. It goes on in every direction and never repeats. The layer
    saves the settings, not pixels;
  - an image, from Import or Convert to Heightmap, placed at a cell. Inside its
    box a corner reads its pixel. Outside, it reads the nearest edge, so ground
    painted past the image carries on at the edge's height and nothing repeats;
  - an image from a level saved before this, which has no place. It is read the
    way it was saved, repeating from cell (0, 0), so an old level shows the same
    ground it showed.

The first time a sculpt touches a chunk, the chunk's samples are filled from the
base and the stroke goes on from there. Filling changes no height, so there is no
seam between a sculpted chunk and the ground beside it. A sculpt writes only
samples, so it changes the ground under the brush and nothing else, on every kind
of base, the old repeating image included.

## Why this shape

My comment on #2007 had every writer fill samples per painted chunk. Two
workflows said otherwise:

- **Paint after Generate Noise.** Painting more ground after the noise is how an
  outdoor level grows, and the noise has to be there when it does. Samples
  written at generation time end at the ground painted then, with flat ground
  past them. So noise stays a field and only a sculpt becomes samples.
- **Import, then paint.** The guide says a heightmap shapes painted cells only,
  so paint after importing. The image has to stay whole for the ground painted
  later, so an import keeps the image and gives it a place.

So the base keeps today's memory: one image, or a few numbers for noise. Samples
cost memory only where a sculpt has been, so two sculpted patches 5,000 cells
apart cost two patches, not the gap.

## Where an image is placed

- **Convert to Heightmap** places its map at the converted box's first cell,
  `cell_min`. The map was already written by `posmod(cell, size)`, and inside its
  own box that is one pixel per cell. So the pixels stay where they are, and a
  build from before this reads the converted ground right inside the box.
- **Import** places the image's top left pixel on the first painted cell of the
  layer, the corner of the painted ground's bounds, or on cell (0, 0) when
  nothing is painted yet. Its pixels are written by `posmod(cell, size)` in the
  same way, so on a layer painted from (0, 0) the file is the same as before.

## The file

All keys are written only when they hold something, so a level saved before this
and saved again writes what it wrote.

| Key | Holds |
| --- | --- |
| `heightmap_b64` | The base image, as before. |
| `heightmap_origin` | `[x, y]`: the cell the image is placed at. Without it the image repeats from (0, 0), as in a level saved before this. |
| `heightmap_noise` | `{type, frequency, octaves, seed}`: the noise the ground is, instead of an image. |
| `height_chunks` | `[{cx, cy, heights}]`: the sculpted samples, each chunk's `heights` encoded as `heightmap_b64` is. |

An older build reads `heightmap_b64` and leaves the rest. So it shows a placed
image repeating, a noise layer flat, and no sculpt made since; its next save
drops all of it. The format fragment says so.

Sculpted samples stay in the level file with the rest of the layer, region
streaming or not. They are a few kilobytes a chunk and only where sculpted; if
that ever matters, they can go into the region files the paint chunks go to.

## What reads heights

`get_height_at(cell)` keeps its signature and meaning, the height at a corner
with the Height Scale applied, so the scatter brush, connectors, overlays and
validation do not change. The heightmap floor builder reads a chunk's 33 by 33
corners once instead of four reads a cell, because a noise corner is a noise
evaluation.

## Pre-mortem

How this could go wrong, and what stops it:

1. **An old level opens with different ground.** No `heightmap_origin` means the
   repeating read, exactly as before. A test loads an old layer and reads cells
   past the image's width.
2. **A sculpt does not undo, or comes back after an undo.** The undo snapshot is
   the same capture as a save, so the samples are in it. A test sculpts, undoes
   and redoes.
3. **A seam where a sculpted chunk meets one that is not.** A chunk is filled from
   the base before the first change to it. A test sculpts across a chunk edge and
   compares the corners there.
4. **A test pins the repeat.** `test_sculpt_wraps_across_the_heightmap_edges` does.
   It is rewritten to say the opposite, not deleted.
5. **Compare calls an old level changed.** No new key is written unless it holds
   something.
6. **A file with another chunk size.** A sculpted chunk whose sample count is not
   the layer's chunk size squared is skipped with a warning, as a paint chunk is.
7. **Noise changes in a later Godot.** Unsculpted noise ground would move with it;
   sculpted chunks keep their samples. FastNoiseLite's output has not changed
   since Godot 4.0, and baking every painted chunk to samples to guard against it
   would cost the memory this design saves.

## After building

- **The comment's plan changed.** It had every writer fill samples per painted
  chunk. Generate Noise and Import stayed a base instead, for the two workflows
  above, and only a sculpt writes samples. Memory stays where it was for an
  untouched layer.
- **Filling is exact to a float.** A noise corner is worked out in 64 bits and
  kept in a 32 bit sample, so a filled chunk reads under a ten millionth of a
  unit off what the noise gave there before. Nothing can see that; the seam test
  allows a millionth.
- **Two tests pinned the repeat.** `test_sculpt_wraps_across_the_heightmap_edges`
  and `test_sculpt_marks_painted_chunks_a_width_away` said a sculpt reaches the
  opposite edge and the chunk a width on. Both now say it does not.
- **The vibe scenario expected the bug.** `terrain-sculpt` reported #2007, #2008
  and #2014 as known. All three are closed, so it flags each as new if it comes
  back. Run against the old sculpt it flags the far hill.
- **The cost.** An older build opens a noise layer flat. Writing an image beside
  the noise for it would put that image into every save and every undo step.
