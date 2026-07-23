# TreeBuilder: Flat-List-to-Tree Conversion Specification

## Overview

This document specifies an Elixir module named `TreeBuilder` that converts a flat
list of maps into a nested tree structure.

Each input item is a map with at least these two fields:
- `:id` — a unique identifier (any term: integer, string, atom)
- `:parent_id` — the id of the parent node, or `nil` if this node is a root

Nodes in the output preserve all original fields from the input map and simply
gain the extra `:children` key. The order of children under each parent follows
the original order those items appeared in the input list. All root-level nodes —
including any orphans raised to root under `:raise_to_root` — appear in their
original input order (a raised orphan keeps its position relative to the real
roots).

The implementation must not use any external dependencies — only the Elixir /
Erlang standard library. The complete module is to be delivered in a single file.

## API

The public API consists of the following function:

- `TreeBuilder.build(items, opts \\ [])` — takes the flat list and returns
  `{:ok, forest}` where `forest` is a list of root-level nodes, each being the
  original map with a `:children` key added (a list of child nodes, recursively
  structured the same way). Leaf nodes have `children: []`. If the input is
  empty, it returns `{:ok, []}`.
  It returns `{:error, {:cycle_detected, ids}}` if a cycle is found, where `ids`
  is the list of node ids involved in the cycle (only the ids that form the
  cycle, in any order).
  It returns `{:error, {:duplicate_ids, ids}}` if any id appears more than once
  in the input, where `ids` is the list of duplicated ids, each listed once
  regardless of how many times it repeats (in any order).

The function must support these options:
- `:orphan_strategy` — what to do when a node's `parent_id` points to an id that
  doesn't exist in the list. Accepted values:
  - `:discard` (default) — silently drop orphan nodes from the output
  - `:raise_to_root` — treat orphans as root nodes

## Edge cases

- An empty input list results in `{:ok, []}`.
- Cycle detection must work for direct cycles (A → B → A) as well as indirect
  ones (A → B → C → A).
- Cycle detection must not false-positive on valid deep trees or on diamond
  shapes that aren't true cycles.
- A cycle must still be detected when the `:raise_to_root` strategy is in effect.
