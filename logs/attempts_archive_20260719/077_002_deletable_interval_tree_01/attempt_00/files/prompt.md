Write me an Elixir module called `DeletableIntervalTree` that implements a persistent, purely-functional interval tree supporting **removal** of intervals with explicit success/failure semantics.

I need these functions in the public API:
- `DeletableIntervalTree.new()` which returns an empty interval tree.
- `DeletableIntervalTree.insert(tree, {start, finish})` which inserts an interval and returns the updated tree. Both `start` and `finish` are integers and `start <= finish` is guaranteed. Duplicate intervals are allowed (inserting `{2, 8}` twice stores two copies).
- `DeletableIntervalTree.delete(tree, {start, finish})` which removes **one** occurrence of the given interval. It returns `{:ok, new_tree}` if the interval was present, or `{:error, :not_found}` if it was not. When two identical intervals are stored, a single `delete` removes only one of them.
- `DeletableIntervalTree.member?(tree, {start, finish})` which returns `true` if at least one copy of the interval is stored, `false` otherwise.
- `DeletableIntervalTree.overlapping(tree, {start, finish})` which returns a list of all stored intervals that overlap the query range. Two intervals overlap if they share at least one point, so `{1, 3}` and `{3, 5}` overlap (touching counts).
- `DeletableIntervalTree.enclosing(tree, point)` which returns a list of all stored intervals that contain the integer `point` (`s <= point <= f`).
- `DeletableIntervalTree.size(tree)` which returns the number of stored intervals.

The tree must be a persistent purely-functional data structure — every `insert` and every successful `delete` returns a new tree value without mutating the input, and the original tree must remain queryable. It should not be a GenServer or process; it's a plain data structure module.

The internal representation must be a proper self-balancing interval tree (an augmented balanced BST where each node stores the maximum `finish` value in its subtree) so that `overlapping` and `enclosing` prune branches efficiently, and so that `insert`/`delete` stay O(log n) with the tree kept balanced after every removal. The `max_finish` augmentation must remain correct after deletions and rebalancing.

Support degenerate intervals where `start == finish`. An empty tree must return `[]` for any query and `0` for `size`.

Give me the complete module in a single file. Use only the Elixir standard library, no external dependencies.