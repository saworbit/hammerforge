# Named, nested groups that open (#1723)

## Where groups stand

A group is a name in `HFVisgroupSystem.groups` and a `group_id` meta on each
member, the name itself. Group Selection names it `group_<usec>`. A click on a
member selects every member (`expand_native_group_selection()`). A node is in one
group, there is no nesting, no list, no label, and Duplicate copies `group_id`, so
the copies of a whole group join it.

## The model

- **The name is the key**, as now, and stays unique. A new name that is taken gets
  a number: "Group of 6 brushes 2". Old levels keep their `group_<usec>` names.
- **Nesting** is `group_parents`, child name to parent name, beside `groups` in the
  level state, the `.hflevel` and the scene's registries. A file without it has no
  nesting, and a build without it reads the groups and drops the nesting.
- A node's `group_id` is its innermost group. Its **chain** is that group and each
  parent out to the top. A group's **members** are the nodes whose chain holds it.
- **Rename** changes the key, the parents that name it, the children that point
  to it, and its direct members' meta, in one undo step.

## Selecting and opening

- **The unit a click selects** is the outermost group in the node's chain. With a
  group **open**, it is the group one level inside the open one, or the node when
  the open group is its own.
- **Open** (double click on a grouped selection, Open in the Groups list, or the
  Open Group command): the selection's top group becomes the open one. A group
  inside it opens one level further in. Everything outside is drawn faded, as a
  locked visgroup is.
- **Close**: Escape, Close Group, or a click on something outside. The open group
  is the editor's state, not the level's: it is not saved and not an undo step.

## Commands

- **Group Selection** asks for a name, with one made from what is selected:
  "Group of 6 brushes", "Group of 2 groups and 1 entity". Whole groups in the
  selection go into the new group as groups. Inside an open group the new group
  is made inside it.
- **Ungroup** takes the selected groups apart one level: their members and the
  groups inside them go to the group around them. Inside an open group, a member
  that is a node of the open group leaves it.
- **Add to Group** puts the selection in the open group, or else the group
  highlighted in the list. **Remove from Group** takes the selection out of the
  open group without taking the rest apart.

## Duplicates

A group whose members are all copied is copied as a new group, "<name> copy",
inside the copy of its parent when that is copied too, and otherwise inside the
same parent. A copy of a node whose group is not wholly copied joins that group,
as copying one member of an open group should. The groups the copies make are
registered by `create_managed_duplicates()`, so a redo makes them again.

## Seeing them

- A **Groups** list in the Visgroups & Groups section: every group in order, the
  nested ones indented under their parents, with the member count. A click selects
  the group. Rename, Open, Add Sel and Remove Sel sit under it.
- The selection readout in the viewport names the group a selection is, and the
  open group.

## Not in this

- Groups in a prefab keep their names and lose their nesting.
- The Agent Bridge's views list groups as they are, without the nesting.
