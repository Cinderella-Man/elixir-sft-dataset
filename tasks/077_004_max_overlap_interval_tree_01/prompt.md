# Specification: `MaxOverlapIntervalTree`

## Overview

This document specifies an Elixir module called `MaxOverlapIntervalTree` that implements a persistent, purely-functional interval tree specialised for **aggregate stabbing-depth queries** rather than interval enumeration.

Unlike a plain interval tree that returns the *list* of matching intervals, this structure answers *counting* questions: how many stored intervals cover a point, and where do the most intervals pile up. Internally the module must maintain a balanced augmented BST (not a flat scan) so the aggregate queries are efficient.

## API

The public API consists of the following functions:

- `MaxOverlapIntervalTree.new()` — returns an empty tree.
- `MaxOverlapIntervalTree.insert(tree, {start, finish})` — inserts a closed integer interval `[start, finish]` and returns the updated tree. Both `start` and `finish` are integers and `start <= finish` is guaranteed. Duplicate intervals may be inserted and are counted with multiplicity. The original `tree` must never be mutated (persistent / purely-functional).
- `MaxOverlapIntervalTree.depth_at(tree, point)` — returns an integer: the number of stored intervals that contain `point`. An interval `[s, f]` contains `point` when `s <= point <= f`. Touching counts, so `[1, 5]` and `[5, 10]` both contain the point `5`.
- `MaxOverlapIntervalTree.max_overlap(tree)` — returns an integer: the maximum number of intervals that simultaneously cover any single integer point (the maximum stabbing number). An empty tree returns `0`.
- `MaxOverlapIntervalTree.busiest_point(tree)` — returns the smallest integer point at which `max_overlap/1` is achieved, or `nil` for an empty tree.

## Implementation constraints

- The intervals are closed and touching is overlapping (so `[1, 3]` and `[3, 5]` both cover point `3`).
- The data must be represented as a **coordinate difference structure inside a balanced BST**: each interval `[s, f]` is modelled as `+1` at coordinate `s` and `-1` at coordinate `f + 1`; those coordinate deltas are kept in a self-balancing (e.g. AVL) tree keyed by coordinate, and each node is augmented so that `max_overlap/1` can be answered from the root's aggregate in `O(log n)`. The implementation must **not** re-sweep every insert or scan a flat list for `max_overlap`. `depth_at/2` must be an `O(log n)` prefix-sum query, not a full traversal.
- It must be a plain data-structure module — not a GenServer or process.

## Edge cases

- Degenerate intervals where `start == finish` (single-point intervals) must be supported.
- An empty tree yields `0` from `max_overlap/1` and `nil` from `busiest_point/1`.
- Duplicate intervals are counted with multiplicity rather than deduplicated.
- Endpoint contact counts as coverage on both sides, per the closed-interval rule above.

## Delivery

The complete module is to be delivered in a single file, using only the Elixir standard library, with no external dependencies.
