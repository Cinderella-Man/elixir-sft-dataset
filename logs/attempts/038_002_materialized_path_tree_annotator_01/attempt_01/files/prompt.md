Write me an Elixir module called `TreePaths` that converts a flat list of maps into a
**flat, pre-order annotated list** — a "materialized path" representation instead of a
nested tree. This is the same domain as a tree builder, but the output shape is different:
rather than nesting children inside parents, every node is annotated with its position in
the hierarchy.

Each input item is a map with at least these two fields:
- `:id` — a unique identifier (any term: integer, string, atom)
- `:parent_id` — the id of the parent node, or `nil` if this node is a root

I need these functions in the public API:

- `TreePaths.build(items, opts \\ [])` — takes the flat list and returns
  `{:ok, nodes}` where `nodes` is a **flat list in pre-order DFS traversal order**
  (each root, then all of that root's descendants depth-first, before moving to the
  next root). Each element is the original map with two extra keys added:
  - `:depth` — an integer; root nodes have depth `0`, their children `1`, and so on.
  - `:path` — a list of ids from the root down to and including this node
    (so a root's path is `[its_id]`, and a grandchild's is `[root_id, parent_id, id]`).

  If the input is empty, return `{:ok, []}`. Returns
  `{:error, {:cycle_detected, ids}}` if a cycle is found, where `ids` is the list of
  node ids involved in the cycle.

- `TreePaths.subtree(nodes, id)` — given the annotated list returned by `build/1` and an
  id, return `{:ok, slice}` where `slice` is the node with that id followed by all of its
  descendants, in pre-order (i.e. every node whose `:path` contains `id`). Returns
  `{:error, :not_found}` if no node with that id is present in `nodes`.

The `build/1` function must support this option:
- `:orphan_strategy` — what to do when a node's `parent_id` points to an id that doesn't
  exist in the list. Accepted values:
  - `:discard` (default) — silently drop orphan nodes (and their descendants) from output
  - `:raise_to_root` — treat orphans as root nodes (depth `0`, path `[id]`)

Order rules: root nodes appear in their original input order; the children of any parent
appear in the original input order those items appeared in the list. All original fields
must be preserved on each node in addition to the new `:depth` and `:path` keys.

Cycle detection must work for direct cycles (A → B → A) as well as indirect ones
(A → B → C → A), and must not false-positive on valid deep trees.

Do not use any external dependencies — only the Elixir / Erlang standard library.
Give me the complete module in a single file.