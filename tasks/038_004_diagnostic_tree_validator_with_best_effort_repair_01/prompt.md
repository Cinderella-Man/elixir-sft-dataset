# TreeValidator: Diagnostic Tree Assembly with Best-Effort Repair

## Overview

This specification describes an Elixir module named `TreeValidator` that converts a flat list of node maps into a nested tree. Instead of fail-fast behavior, the module operates with **collect-all diagnostics and best-effort repair** semantics. Rather than stopping at the first problem, it gathers *every* structural issue present in the input, builds the best tree it can from the healthy remainder, and reports what it had to work around.

Each node is a map that is guaranteed to have an `:id` field (a unique identifier: integer, string, or atom). The `:parent_id` field may or may not be present; when it is absent, the node is treated as a root (and reported — see the Edge cases section). A present `:parent_id` holds the parent's id, or `nil` for a root.

The module must not use any external dependencies — only the Elixir / Erlang standard library. The complete module is to be delivered in a single file.

## API

The module exposes one public function:

- `TreeValidator.build(items)` — returns one of the following:
  - `{:ok, forest}` when the input has **no** structural issues. Here `forest` is a list of root-level nodes, each being the original map plus a `:children` key (recursively the same shape); leaves have `children: []`. Empty input returns `{:ok, []}`.
  - `{:issues, forest, issues}` when one or more issues were found. Here `forest` is the **best-effort** tree (possibly empty), and `issues` is a non-empty list describing every problem.

Each issue is a map of the form `%{type: atom(), ids: [term()]}`.

## Edge cases

The module must detect these four issue types:

- `:duplicate_id` — one entry, whose `ids` are the ids that appeared more than once (in first-seen order). Repair: keep the **first** occurrence of each id; drop later duplicates.
- `:missing_parent_id` — one entry, whose `ids` are the ids of nodes that lack the `:parent_id` key (in input order). Repair: treat each such node as a root.
- `:orphan` — one entry, whose `ids` are the ids of nodes whose `parent_id` points to an id not present in the (deduplicated, non-cyclic) node set. Repair: raise each orphan to a root.
- `:cycle` — one entry **per distinct cycle**, whose `ids` are the ids forming that cycle. Repair: remove all nodes on the cycle from the forest (a non-cyclic node that referenced a removed cycle node then becomes an orphan, handled by the `:orphan` rule).

Ordering of the `issues` list: the `:duplicate_id` entry (if any) comes first, then `:missing_parent_id`, then `:orphan`, then one `:cycle` entry per cycle. Within the best-effort forest, root order and sibling order follow the original input order (after deduplication).

The result must always contain a usable `forest`, even when several different issues occur together in a single input. Cycle handling must catch both direct cycles (A → B → A) and indirect cycles (A → B → C → A), and must not misreport valid deep trees.
