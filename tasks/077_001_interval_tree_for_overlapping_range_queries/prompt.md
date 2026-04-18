Write me an Elixir module called `IntervalTree` that implements an interval tree for efficient overlapping range queries.

I need these functions in the public API:
- `IntervalTree.new()` which returns an empty interval tree.
- `IntervalTree.insert(tree, {start, finish})` which inserts an interval into the tree and returns the updated tree. Both `start` and `finish` are integers, and `start <= finish` is guaranteed.
- `IntervalTree.overlapping(tree, {start, finish})` which returns a list of all intervals stored in the tree that overlap with the query range. Two intervals overlap if they share at least one point — so `{1, 3}` and `{3, 5}` are considered overlapping (touching counts).
- `IntervalTree.enclosing(tree, point)` which returns a list of all intervals stored in the tree that contain the given integer point. An interval `{s, f}` contains `point` if `s <= point <= f`.

The tree must be a persistent purely-functional data structure — every `insert` returns a new tree value without mutating the input. It should not be a GenServer or process; it's a plain data structure module.

The internal representation should be a proper interval tree (augmented BST where each node stores the maximum `finish` value in its subtree) so that `overlapping` and `enclosing` can prune branches efficiently, not a flat list scan.

Support degenerate intervals where `start == finish` (a single-point interval). An empty tree must return `[]` for any query.

Give me the complete module in a single file. Use only the Elixir standard library, no external dependencies.