# On the Use of AI

People ask whether AI helped build HammerForge often enough that it deserves one
real answer instead of a slightly different half-answer each time.

Yes. Extensively. Here is the whole position, including the parts that flatter it
less.

## The short version

I use AI assistants throughout this project: writing code, reviewing code I wrote
by hand, drafting documentation, and arguing through design problems I had not yet
resolved. I do not take what comes back and ship it. Everything here has been
read, run, and tested, and a good deal of it has been thrown away and done again.

That is not a confession and it is not a sales pitch. It is how this was made, and
you should be able to find that out without inferring it from the presence of
`addons/godot_mcp`.

## A level editor is in no position to object

HammerForge exists because placing every vertex by hand is a poor use of a
designer's afternoon. That is the entire premise, and it is not original to me —
it is the premise of Hammer, of TrenchBroom, and of every brush-based editor in
that lineage. The interesting part of level design is deciding where the room
goes. The rest is getting the geometry to agree with the decision, and that part
has been worth automating since 1996.

So a tool built to remove tedium, built using tools that remove tedium, is not a
contradiction. It is the same conviction applied one level up. I would find it
strange to spend this long automating the tedious parts of blockout while treating
the tedious parts of writing the automation as sacred.

Labour saved is not the interesting question. The interesting questions are
whether the result is any good, and whether somebody is answerable for it.

## What "did you write this?" is actually asking

Underneath that question is a better one: *who do I hold responsible when it
breaks?*

Me. Without qualification, and without an asterisk pointing at a model.

Every line in this repository is a line I chose to ship. If a brush bakes with
inverted winding, if a cut corrupts your level file, if an undo step eats your
work — that is mine. Not partly mine. Not mine-with-context. The provenance of a
suggestion has no bearing on who owns the decision to accept it, and I have never
found the distinction between code I typed and code I approved to be as morally
significant as it is usually made out to be. Both are choices. Both are mine.

This is also why I am relaxed about disclosing it. Authorship, in the sense that
matters to you as a user, was never about keystrokes. It is about accountability,
and that has not moved.

## What actually checks it

The claim "I test what it produces" is worth nothing on its own — anyone can write
that sentence. So instead, here is what runs, all of it in this repository and all
of it runnable by you:

- **The GUT suite** in `tests/`, several thousand tests, run headless in CI on
  every pull request and every push to `main`.
- **`tools/check_placement_order.py`**, a static guard for one specific bug class,
  with a `--selftest` that runs first so a detector which has quietly stopped
  detecting fails loudly rather than passing everything.
- **`gdformat` and `gdlint`** over every line of GDScript.
- **`ruff`** over the Python tooling, **`actionlint`** and **`zizmor`** over the
  CI workflows themselves.
- **A protected `main`** that takes no direct pushes from anyone, including me and
  including CI. Every change arrives as a pull request with three green checks.

None of that exists because of AI. It exists because I am one person and this is
more code than one person can hold in their head. But it is the reason I am
willing to work this way: the verification is the load-bearing part, and it does
not care where a line came from.

## Where it does not help

This is the section that makes the rest believable, so it is specific.

**It is confidently wrong about Godot.** The engine's API surface moves, and
assistants will cheerfully call `Image.load()`, which Godot 4 removed, or reach
for `undo()` on `EditorUndoRedoManager`, which has never had it. Every one of
those cost me time before it cost me nothing, because I now keep notes.

**It reasons poorly about space.** Face winding is clockwise from outside. A basis
with a negative determinant inverts that winding invisibly — nothing looks wrong
until you bake. This is exactly the class of error a model will not catch, and
frankly one I miss by eye too.

**It repeats mistakes convincingly.** A world transform assigned to a node before
that node is in the tree writes the local transform instead, and the node lands
shifted by its container. That bug has been fixed here six times, most recently in
the baker, where it was applying the root transform twice to geometry that ships.
Six times. The response was not to try harder; it was to write
`tools/check_placement_order.py` so the build refuses it. That guard is the honest
artefact of this whole arrangement — proof that I do not trust the process, mine
or a model's, without something mechanical standing behind it.

**It does not know when the approach is wrong.** It will help you build the wrong
thing beautifully. Deciding what not to build is still entirely manual, and it is
most of the job.

I still write code by hand — often the parts I care most about — and then have it
reviewed. The traffic goes both ways.

## About the art

**No image models were used anywhere in this project.** This matters more to some
readers than the code does, so here is precisely how each asset was made:

- **The mark and wordmark** are custom-drawn SVG on a 100-unit grid — kerf 3u,
  ring 14u — with a compact weight for small sizes. Sources in `docs/brand/svg/`,
  rasterised by `docs/brand/build.py` and `raster.js`. The geometry is a
  deliberate reference to the outline HammerForge draws around subtract brushes.
  See [BRAND.md](docs/brand/BRAND.md).
- **The 150 prototype textures** are generated by script as SVG, not sampled or
  synthesised. See [Prototype Textures](docs/HammerForge_Prototype_Textures.md).
- **Every screenshot and clip** is real editor output. The showcase scene is built
  by `tools/build_showcase_scene.gd` and captured by `tools/capture_showcase.gd`.
  The hall on the README is 81 brushes, drawn with the tools it is advertising.

If that ever changes, it will say so here first.

## If you would rather not

Some people want nothing to do with software built this way. That is a coherent
position, held for reasons ranging from labour to provenance to taste, and I am
not going to argue you out of it.

What I do think is that you are owed the information without having to dig for it,
which is why this file exists at the root of the repository rather than in a
footnote. Read it, decide, and use something else with my genuine good wishes if
that is where you land.

For what it is worth, my own view is narrower than the argument usually gets: I
think a tool is worth using if it lets one person hold more of a hard problem at
once, and worth distrusting to exactly the degree that nothing is checking its
output. Both halves matter. I have tried to build the second half into this
repository in a way you can run yourself.

---

**Contributors:** the related question — whether *you* can use AI on a pull
request — is answered in [CONTRIBUTING.md](CONTRIBUTING.md#ai-assisted-contributions).
The short version is yes, on the same terms.
