Write me an Elixir module called `MaxOverlapIntervalTree` that implements a persistent, purely-functional interval tree specialised for **aggregate stabbing-depth queries** rather than interval enumeration.

Unlike a plain interval tree that returns the *list* of matching intervals, this structure answers *counting* questions: how many stored intervals cover a point, and where do the most intervals pile up. Internally you must maintain a balanced augmented BST (not a flat scan) so the aggregate queries are efficient.

I need these functions in the public API:
- `MaxOverlapIntervalTree.new()` which returns an empty tree.
- `MaxOverlapIntervalTree.insert(tree, {start, finish})` which inserts a closed integer interval `[start, finish]` and returns the updated tree. Both `start` and `finish` are integers and `start <= finish` is guaranteed. Duplicate intervals may be inserted and are counted with multiplicity. The original `tree` must never be mutated (persistent / purely-functional).
- `MaxOverlapIntervalTree.depth_at(tree, point)` which returns an integer: the number of stored intervals that contain `point`. An interval `[s, f]` contains `point` when `s <= point <= f`. Touching counts, so `[1, 5]` and `[5, 10]` both contain the point `5`.
- `MaxOverlapIntervalTree.max_overlap(tree)` which returns an integer: the maximum number of intervals that simultaneously cover any single integer point (the maximum stabbing number). An empty tree returns `0`.
- `MaxOverlapIntervalTree.busiest_point(tree)` which returns the smallest integer point at which `max_overlap/1` is achieved, or `nil` for an empty tree.

Implementation constraints:
- The intervals are closed and touching is overlapping (so `[1, 3]` and `[3, 5]` both cover point `3`).
- Represent the data as a **coordinate difference structure inside a balanced BST**: model each interval `[s, f]` as `+1` at coordinate `s` and `-1` at coordinate `f + 1`, keep those coordinate deltas in a self-balancing (e.g. AVL) tree keyed by coordinate, and augment each node so that `max_overlap/1` can be answered from the root's aggregate in `O(log n)` — do **not** re-sweep every insert or scan a flat list for `max_overlap`. `depth_at/2` must be an `O(log n)` prefix-sum query, not a full traversal.
- Support degenerate intervals where `start == finish` (single-point intervals).
- It must be a plain data-structure module — not a GenServer or process.

Give me the complete module in a single file. Use only the Elixir standard library, no external dependencies.