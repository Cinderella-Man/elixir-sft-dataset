Write me an Elixir module called `TreeStream` — a **stateful GenServer** that builds a
nested tree from node maps that arrive **incrementally and possibly out of order**
(a child may be added before its parent). Unlike a one-shot builder, this process
accumulates nodes over time and can be queried for the current forest at any moment.

Each node is a map with at least these two fields:
- `:id` — a unique identifier (any term: integer, string, atom)
- `:parent_id` — the id of the parent node, or `nil` if this node is a root

I need this public API:

- `TreeStream.start_link(opts \\ [])` — starts the server and returns `{:ok, pid}`.
  Supported option:
  - `:orphan_strategy` — `:discard` (default) or `:raise_to_root`, applied when the
    forest is computed (see below).

- `TreeStream.add(server, item)` — adds one node. Returns `:ok`, or
  `{:error, {:duplicate_id, id}}` if a node with that id was already added (the new
  item is rejected and state is unchanged).

- `TreeStream.add_many(server, items)` — adds a list of nodes in order. Nodes whose id
  is already present (from a previous call or earlier in the same list) are skipped.
  Always returns `:ok`.

- `TreeStream.forest(server)` — computes and returns `{:ok, forest}` from all nodes added
  so far, where `forest` is a list of root-level nodes, each being the original map with a
  `:children` key added (a list of child nodes, recursively structured the same way).
  Leaf nodes have `children: []`. When no nodes have been added, returns `{:ok, []}`.
  Returns `{:error, {:cycle_detected, ids}}` if the current set of nodes contains a cycle,
  where `ids` is a list of the node ids participating in the cycle (in no particular order).

- `TreeStream.count(server)` — returns the number of nodes currently held (an integer).
  This counts every node that was added, including orphans and nodes that never appear in
  the forest.

- `TreeStream.stop(server)` — stops the server and returns `:ok`.

Ordering rules for `forest/1`: root nodes appear in the order they were added; the
children of any parent appear in the order those items were added. All original fields
must be preserved, with only the extra `:children` key added.

Because nodes arrive incrementally, `forest/1` must correctly handle the case where a
child was added before its parent — the resulting nesting must be identical regardless of
insertion order (only the *root order* and *sibling order* follow insertion order).

`:orphan_strategy` governs nodes whose `parent_id` references an id not currently present:
`:discard` drops them, `:raise_to_root` promotes them to roots. When a node is dropped
under `:discard`, any nodes reachable only through it (its descendants) are also absent
from the forest, even though their own `parent_id` refers to a present node. Cycle
detection must catch both direct (A → B → A) and indirect (A → B → C → A) cycles.

Do not use any external dependencies — only the Elixir / Erlang standard library.
Give me the complete module in a single file.
