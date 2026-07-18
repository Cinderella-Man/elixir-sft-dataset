Write me an Elixir module called `IntervalTree` that implements an interval tree for efficient overlapping range queries.

## Public API

- `IntervalTree.new()` — returns an empty interval tree.
- `IntervalTree.insert(tree, {start, finish})` — inserts an interval into the tree and returns the updated tree. Both `start` and `finish` are integers, and `start <= finish` is guaranteed.
- `IntervalTree.overlapping(tree, {start, finish})` — returns a list of all intervals stored in the tree that overlap with the query range.
- `IntervalTree.enclosing(tree, point)` — returns a list of all intervals stored in the tree that contain the given integer point.

All four functions return plain values, not `{:ok, _}` / `{:error, _}` tuples: `new/0` and `insert/2` return a tree value, and the two query functions return a list of `{start, finish}` tuples. There is no error path — inputs are assumed to be well-formed (integer endpoints, `start <= finish`), and the module does not validate them or raise on its own.

## Data structure requirements

The tree must be a persistent, purely-functional data structure — every `insert` returns a new tree value without mutating the input. Any tree value a caller holds on to stays queryable and unchanged forever, no matter how many further inserts derive from it, so `t1 = insert(t0, iv)` leaves `t0` answering queries exactly as it did before. It is not a GenServer or process; it's a plain data structure module.

The internal representation must be a proper interval tree: an augmented, self-balancing binary search tree keyed on `start`, where each node also stores the maximum `finish` value across its subtree. `overlapping/2` and `enclosing/2` must use that augmentation (plus BST ordering on `start`) to prune whole branches instead of visiting every node — a flat list scan is not acceptable. Insert must keep the tree balanced (AVL-style rebalancing after each insertion), so with `n` stored intervals and `k` matching results the costs are:

- `insert/2` — O(log n)
- `overlapping/2` — O(log n + k)
- `enclosing/2` — O(log n + k)

Represent the empty tree as a value the module itself defines (whatever `new/0` returns); the queries must accept it directly.

## Query semantics

**Overlap.** Two intervals overlap if they share at least one point: `{s1, f1}` overlaps `{s2, f2}` exactly when `s1 <= f2` and `f1 >= s2`. Touching counts — `{1, 3}` and `{3, 5}` overlap. Boundaries are therefore inclusive on both ends: a query `{3, 3}` against a stored `{1, 3}` matches, and a query `{4, 9}` against a stored `{1, 3}` does not.

**Enclosure.** An interval `{s, f}` contains `point` exactly when `s <= point <= f`. The endpoints themselves count: for a stored `{1, 5}`, both `enclosing(tree, 1)` and `enclosing(tree, 5)` include it, while `enclosing(tree, 6)` does not.

**Degenerate intervals.** `start == finish` is a legal, single-point interval and must behave like any other: `{7, 7}` is returned by `enclosing(tree, 7)`, by `overlapping(tree, {7, 7})`, and by any query range that includes 7. A degenerate *query* range `{p, p}` is likewise legal and returns exactly the intervals that contain `p` — the same set `enclosing(tree, p)` returns.

## Edge cases and observable contract

- **Empty tree.** `overlapping(new(), _)` and `enclosing(new(), _)` both return `[]` for any query, without raising.
- **No matches.** A query on a non-empty tree that nothing matches returns `[]`, not an error.
- **Duplicates are kept.** Inserting the same interval twice stores it twice. A query that matches it returns it twice — one entry per insertion. The tree is a multiset of intervals; there is no de-duplication and no "already present" signalling.
- **Result ordering is unspecified.** Neither query function guarantees any particular order for the returned intervals. Callers who need a deterministic order must sort the result themselves. The only guarantee is set-membership (multiset, including duplicates): every matching stored interval appears exactly as many times as it was inserted, and nothing else appears.
- **Queries are pure.** Calling `overlapping/2` or `enclosing/2` never changes the tree; repeated identical calls on the same tree value return the same multiset of intervals. Insertion order may affect the internal shape of a balanced tree, but never the multiset a query returns.
- **Insert accepts intervals in any order.** Intervals may be inserted in ascending, descending, or arbitrary `start` order; the tree stays balanced and queries stay correct in every case. Intervals sharing the same `start` are all retained.

Give me the complete module in a single file. Use only the Elixir standard library, no external dependencies.
