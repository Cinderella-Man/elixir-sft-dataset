Write me an Elixir module called `TreeBuilder` that converts a flat list of maps into a
nested tree structure.

Each input item is a map with at least these two fields:
- `:id` — a unique identifier (any term: integer, string, atom)
- `:parent_id` — the id of the parent node, or `nil` if this node is a root

I need these functions in the public API:

- `TreeBuilder.build(items, opts \\ [])` — takes the flat list and returns
  `{:ok, forest}` where `forest` is a list of root-level nodes, each being the
  original map with a `:children` key added (a list of child nodes, recursively
  structured the same way). Leaf nodes have `children: []`. If the input is
  empty, return `{:ok, []}`.
  Returns `{:error, {:cycle_detected, ids}}` if a cycle is found, where `ids` is
  the list of node ids involved in the cycle.

The function must support these options:
- `:orphan_strategy` — what to do when a node's `parent_id` points to an id that
  doesn't exist in the list. Accepted values:
  - `:discard` (default) — silently drop orphan nodes from the output
  - `:raise_to_root` — treat orphans as root nodes

Nodes in the output should preserve all original fields from the input map and
simply gain the extra `:children` key. The order of children under each parent
should follow the original order those items appeared in the input list. Root
nodes should also appear in their original input order.

Cycle detection must work for direct cycles (A → B → A) as well as indirect
ones (A → B → C → A). It must not false-positive on valid deep trees or on
diamond shapes that aren't true cycles.

Do not use any external dependencies — only the Elixir / Erlang standard library.
Give me the complete module in a single file.