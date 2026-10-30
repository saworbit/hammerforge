---
title: Translating HammerForge
description: "How HammerForge shows its words in the editor's language, how to start a language from hammerforge.pot, and what a contributor does when adding a label."
---

# Translating HammerForge

HammerForge keeps its words in a translation domain of its own, `hammerforge`
([#1702](https://github.com/saworbit/hammerforge/issues/1702)). Its catalogs
never change one of the editor's words, and the editor's catalogs never change
one of HammerForge's. Before this, a dock inside an editor running in another
language had some of its words translated by the editor's own catalogs and the
rest left in English.

## What follows the editor's language

- The labels, tooltips, menu items and tab titles of the dock, the Console, the
  shortcut HUD, the overlays over the viewport and HammerForge's dialogs.
- Each command's name, category and help, in the command palette and the
  shortcut dialog. The palette finds a command by its name in the language
  shown and by its English name, and shows which one matched.
- Toasts and the dock's status line, and the text HammerForge puts together in
  code with a number or a name in it before it shows it.

A refusal a tool or a command reports, such as "Arch: radius must be greater
than zero", reads the same way: English for the log and the bridge, and in the
language shown on screen. Text that reaches the screen by a path the ratchet
below does not read may still be English.

These stay English in every language, so a bug report and an agent read the
same words:

- command ids, which keymaps and the Agent Bridge depend on;
- the Console's log;
- the bridge's replies and error codes.

## Start a language

1. Copy `addons/hammerforge/translations/hammerforge.pot` to
   `addons/hammerforge/translations/<locale>.po` beside it, for example `es.po`.
2. Set its header: `"Language: es\n"`, and the `Plural-Forms` line for the
   language.
3. Fill in each `msgstr`. One left empty stays English.
4. Turn HammerForge off and on again under **Project > Project Settings >
   Plugins**, or restart the editor. HammerForge loads every `.po` file in
   `translations/` when it starts, and shows the one for the editor's language,
   **Editor Settings > Interface > Editor > Editor Language**.

Keep every placeholder in braces as it is, and translate the words around it:
`"Repeat: {command}"` can become `"Repetir: {command}"`, never
`"Repetir: {comando}"`. A test checks every catalog in `translations/` for this,
and for printf placeholders such as `%d` kept in their order.

## Adding a label

`addons/hammerforge/translations/hammerforge.pot` is written by
`tools/gen_pot.gd`. After changing a word HammerForge shows, run:

```bash
godot --headless -s res://tools/gen_pot.gd --path .
```

`tests/test_translation.gd` fails until the committed file is what it writes.

The tool finds a word in these places, much as Godot finds a game's:

- a command's `label`, `category` and `help` in `hf_command_registry.gd`;
- a literal assigned whole to `text`, `tooltip_text`, `placeholder_text`,
  `title` or `dialog_text`, including literals joined with `+` and each branch
  of `"a" if x else "b"`;
- a literal given to `add_item()`, `set_item_text()`, `set_tab_title()`,
  `set_text()` and the other calls `tools/pot_catalog.gd` lists in `CALLS`;
- a literal given to `show_toast()`, `_set_status()` and the other toast and
  status calls in `CALLS`, or sent with the level's `user_message` signal. The
  toast shows it in the language shown, and the Console's log and the bridge
  keep it in English;
- a literal given to `HFTranslation.t()` or `HFTranslation.tn()`;
- a literal a table holds under `"label"`, `"tooltip"`, `"help"`, `"title"` or
  `"blurb"`, such as a structure's fields and the Console's Controls. The
  control the table fills looks it up. Code that draws a table's word itself,
  like the radial menu, puts it through `HFTranslation.t()` first;
- the same properties in the addon's `.tscn` scenes.

A control in HammerForge's domain looks its own text up, so a label set from a
literal needs nothing more. Text put together in code goes through
`HFTranslation.t()` before anything is put in it, with named placeholders:

```gdscript
var text := HFTranslation.t("Removed {count} unused materials").format({"count": n})
```

not `"Removed %d unused material%s" % [n, "s" if n != 1 else ""]`. A count that
changes the words uses `HFTranslation.tn()`, which knows each language's plural
rules:

```gdscript
HFTranslation.tn("{count} brush", "{count} brushes", n).format({"count": n})
```

A message the Console's log or the bridge reads as well as the mapper, such as
one sent with the level's `user_message` signal, a status line that is an error
or a warning, or a refusal in an `HFOpResult`, goes through
`HFTranslation.message()` or `HFTranslation.message_n()` instead. Each takes the
English and the values, and gives back the message in English, so the log and
an agent read it as it is in every language. The toast and the status line show
it in the language shown:

```gdscript
var said := HFTranslation.message_n("Scattered {count} instance", "Scattered {count} instances", n)
root.user_message.emit(said, 0)
```

`HFOpResult.fail()` and `success()` do this for a plain literal themselves. A
refusal put together in code is made with `message()` first.

A sentence with two counts gives each its own `message_n()` and takes them as
words, the third argument, so each count gets the plural its language needs:

```gdscript
var parts := {
	"brushes": HFTranslation.message_n("{count} brush", "{count} brushes", b),
	"entities": HFTranslation.message_n("{count} entity", "{count} entities", e),
}
var said := HFTranslation.message("Pasted {brushes} and {entities}", {}, parts)
```

About a thousand strings were put together the old way before this was
possible. `tests/test_untranslated_text_ratchet.gd` counts, for each script,
the formatted strings handed straight to a label, a tooltip, a title or a
toast, or sent with `user_message`, without `HFTranslation.t()`, `tn()` or
`message()`, and keeps the counts in
`tests/fixtures/untranslated_interface_text.json`. It fails when a script's
count goes up, so new text goes through the catalogs. It also fails when a
count goes down, until that script's line in the file is lowered to match, so
the counts only move one way. Run it with `HF_RATCHET_WRITE=1` set to write the
counts as they are.

A new surface the plugin puts in the editor's own tree, outside the dock, is
given the domain with `HFTranslation.adopt(node)` before it goes in. A dialog
added with the plugin's `_add_confirmable_dialog()` and an overlay attached
with `HFPluginOverlays.attach_viewport_overlay()` are given it already.
