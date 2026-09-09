# On the Use of AI

I get asked whether AI helped build HammerForge. It comes up often enough that it
is worth writing down once.

Yes. Quite a lot of it. Here is the honest version.

## The short answer

I use AI assistants for a lot of this project. Writing code, reviewing code I
wrote myself, drafting documentation, thinking through design problems before I
commit to one of them.

I do not paste what comes back and ship it. Everything here has been read, run and
tested, and plenty of it has been thrown away and done again.

That is not something I feel I need to apologise for, and it is not something I am
selling either. It is just how this got made. You should be able to find that out
without working it out from the MCP server sitting in `addons/godot_mcp`.

That includes the writing. Some of the commit messages and parts of these docs
were drafted with help, and it shows in places. I would rather say so here than
have you spot it and wonder what else went unmentioned.

## Why I am comfortable with it

HammerForge exists because placing every vertex by hand is a slow way to spend an
afternoon. That is the whole idea, and it is not mine. It is what Hammer and
TrenchBroom were for. The interesting part of level design is working out where
the room goes. Making the geometry agree with that decision is the boring part,
and people have been automating it since the nineties.

So building a tool that removes tedious work, using tools that remove tedious
work, seems consistent to me rather than contradictory.

What matters is not how much effort got saved. It is whether the result works, and
whether someone is on the hook when it does not.

## Who is responsible

When people ask whether I wrote this, I think the real question is who to blame
when it breaks.

That is me.

Every line in here is a line I decided to ship. If a brush bakes with its faces
inside out, if a cut corrupts your level file, if undo eats your work, that is
mine. Where a suggestion came from does not change who chose to accept it. I have
never found the line between code I typed and code I approved to be as meaningful
as it usually gets treated.

That is also why I am relaxed about saying all this. The part that matters to you
was never about who pressed the keys.

## What actually checks it

Saying "I test what it produces" is easy and worth very little on its own. So here
is what actually runs. All of it is in this repository and you can run it
yourself.

- The GUT suite in `tests/`. Several thousand tests, run headless in CI on every
  pull request and every push to `main`.
- `tools/check_placement_order.py`, a static check for one specific bug. It tests
  itself first, so a check that has quietly stopped working fails loudly instead
  of passing everything.
- `gdformat` and `gdlint` across all the GDScript.
- `ruff` on the Python tooling, plus `actionlint` and `zizmor` on the CI workflows.
- A protected `main` that takes no direct pushes from anyone, including me and
  including CI. Everything arrives as a pull request with green checks.

None of that is there because of AI. It is there because I am one person and this
is more code than I can keep in my head. But it is the reason I am willing to work
this way. The checking is the part carrying the weight, and it does not care where
a line came from.

## Where it is not much help

This is the part that makes the rest worth believing, so it is specific.

**It gets Godot wrong with confidence.** The engine moves and assistants will
happily call `Image.load()`, which Godot 4 removed, or reach for `undo()` on
`EditorUndoRedoManager`, which never had it. Each of those cost me time before I
started keeping notes.

**It is poor at spatial reasoning.** Face winding is clockwise from outside. A
basis with a negative determinant flips that invisibly, and nothing looks wrong
until you bake. That is not something a model catches. I miss it by eye too, to be
fair.

**It repeats the same mistake convincingly.** Assigning a world transform to a
node that is not in the tree yet writes the local transform instead, and the node
ends up offset by its parent. That has been fixed here six times. The most recent
was in the baker, applying the root transform twice to geometry that ships. After
six times the answer was not to be more careful. It was to write
`tools/check_placement_order.py` so the build refuses it.

**It does not know when the idea is wrong.** It will help you build the wrong
thing very well. Deciding what not to build is still entirely on me, and that is
most of the work.

I still write plenty by hand, usually the parts I care about most, and then have
it reviewed. It goes both ways.

## The art

No image models were used anywhere in this project. That matters more to some
people than the code does, so here is how each thing was actually made.

- The mark and wordmark are drawn by hand as SVG on a 100 unit grid, with a
  compact version for small sizes. Sources are in `docs/brand/svg/`, rasterised by
  `docs/brand/build.py` and `raster.js`. See [BRAND.md](docs/brand/BRAND.md).
- The 150 prototype textures are generated by script as SVG. See
  [Prototype Textures](docs/HammerForge_Prototype_Textures.md).
- Every screenshot and clip is real editor output. The showcase scene is built by
  `tools/build_showcase_scene.gd` and captured by `tools/capture_showcase.gd`. The
  hall on the README is 81 brushes, drawn with the tools it is showing off.

If that ever changes I will say so here first.

## If you would rather not

Some people want nothing to do with software built this way. That is a fair
position to hold and I am not going to try to talk anyone out of it.

I do think you are owed the information without having to go looking for it, which
is why this sits at the root of the repository rather than buried somewhere. Read
it, make your own call, and go use something else with no hard feelings if that is
where you land.

My own view is fairly narrow. A tool is worth using if it lets one person hold
more of a hard problem at once. It is worth distrusting to exactly the degree that
nothing is checking its output. I have tried to build the second half into this
repository so you can run it yourself.

Contributors: whether you can use AI on a pull request is answered in
[CONTRIBUTING.md](CONTRIBUTING.md#ai-assisted-contributions). Short answer is yes,
on the same terms.
