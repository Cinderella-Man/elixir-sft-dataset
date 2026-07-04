Write me an Elixir module called `TreeValidator` that converts a flat list of node maps
into a nested tree, but with **collect-all diagnostics and best-effort repair** semantics
instead of fail-fast. Rather than stopping at the first problem, it gathers *every*
structural issue in the input, builds the best tree it can from the healthy remainder, and
reports what it had to work around.

Each node is a map that is guaranteed to have an `:id` field (a unique identifier: integer,
string, or atom). The `:parent_id` field may or may not be present; when absent, treat the
node as a root (and report it — see below). A present `:parent_id` is the parent's id, or
`nil` for a root.

I need this single public function:

- `TreeValidator.build(items)` — returns one of:
  - `{:ok, forest}` when the input has **no** structural issues. `forest` is a list of
    root-level nodes, each being the original map plus a `:children` key (recursively the
    same shape); leaves have `children: []`. Empty input returns `{:ok, []}`.
  - `{:issues, forest, issues}` when one or more issues were found. `forest` is the
    **best-effort** tree (possibly empty), and `issues` is a non-empty list describing
    every problem.

Each issue is a map `%{type: atom(), ids: [term()]}`. Detect these four types:

- `:duplicate_id` — one entry, `ids` = the ids that appeared more than once (in first-seen
  order). Repair: keep the **first** occurrence of each id; drop later duplicates.
- `:missing_parent_id` — one entry, `ids` = ids of nodes that lack the `:parent_id` key
  (in input order). Repair: treat each as a root.
- `:orphan` — one entry, `ids` = ids of nodes whose `parent_id` points to an id not present
  in the (deduplicated, non-cyclic) node set. Repair: raise each orphan to a root.
- `:cycle` — one entry **per distinct cycle**, `ids` = the ids forming that cycle. Repair:
  remove all nodes on the cycle from the forest (a non-cyclic node that referenced a removed
  cycle node then becomes an orphan, handled by the `:orphan` rule).

Ordering of the `issues` list: put the `:duplicate_id` entry (if any) first, then
`:missing_parent_id`, then `:orphan`, then one `:cycle` entry per cycle. Within the
best-effort forest, root order and sibling order follow the original input order (after
deduplication).

The result must always contain a usable `forest`, even when several different issues occur
together in one input. Cycle handling must catch both direct (A → B → A) and indirect
(A → B → C → A) cycles, and must not misreport valid deep trees.

Do not use any external dependencies — only the Elixir / Erlang standard library.
Give me the complete module in a single file.