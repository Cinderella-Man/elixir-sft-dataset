Write me an Elixir module called `IntervalCounter` that implements a persistent, purely-functional interval tree specialized for **aggregate counting** queries rather than enumeration — the kind of thing you'd use to answer "how busy is this schedule?".

I need these functions in the public API:
- `IntervalCounter.new()` which returns an empty structure.
- `IntervalCounter.insert(tree, {start, finish})` which inserts an interval and returns the updated structure. Both `start` and `finish` are integers with `start <= finish`. Duplicate intervals are allowed.
- `IntervalCounter.count_overlapping(tree, {start, finish})` which returns the integer **number** of stored intervals that overlap the query range (not the intervals themselves). Two intervals overlap if they share at least one point, so `{1, 3}` and `{3, 5}` overlap (touching counts).
- `IntervalCounter.count_enclosing(tree, point)` which returns the integer number of stored intervals that contain the integer `point` (the "stabbing count" — how many intervals cover that point).
- `IntervalCounter.max_concurrent(tree)` which returns the maximum number of stored intervals that overlap at any single point across the whole timeline — i.e. the peak concurrency. It returns `0` for an empty structure. Because touching counts as overlap, two intervals `{1, 3}` and `{3, 5}` produce a peak of `2` (both cover point `3`), while `{1, 2}` and `{3, 4}` produce a peak of `1`.
- `IntervalCounter.size(tree)` which returns the number of stored intervals.

The structure must be a persistent purely-functional value — every `insert` returns a new value without mutating the input. It should not be a GenServer or process.

The internal representation must be a proper interval tree (an augmented balanced BST where each node stores the maximum `finish` in its subtree) so that `count_overlapping` and `count_enclosing` prune branches efficiently instead of scanning every interval. `max_concurrent` may traverse all stored intervals but must compute the true peak concurrency using the touching-counts-as-overlap rule.

Support degenerate intervals where `start == finish`. An empty structure returns `0` for every count query.

Give me the complete module in a single file. Use only the Elixir standard library, no external dependencies.