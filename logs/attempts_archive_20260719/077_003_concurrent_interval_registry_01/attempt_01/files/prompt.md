Write me an Elixir module called `IntervalRegistry` that provides a **concurrent, process-backed** interval store for overlapping range queries. Unlike a plain data structure, this is a stateful server that many client processes can share.

Implement it as a `GenServer` with this public API:
- `IntervalRegistry.start_link(opts \\ [])` which starts the server and returns `{:ok, pid}`. It must accept standard `GenServer` options (e.g. `:name`).
- `IntervalRegistry.stop(server)` which stops the server.
- `IntervalRegistry.insert(server, {start, finish})` which stores an interval and returns `{:ok, id}` where `id` is a unique integer handle for that stored interval. Both `start` and `finish` are integers with `start <= finish`. Inserting identical intervals is allowed and each gets its own id.
- `IntervalRegistry.remove(server, id)` which removes the interval previously stored under `id`. It returns `:ok` if that id was present, or `{:error, :not_found}` if it was not (or was already removed).
- `IntervalRegistry.overlapping(server, {start, finish})` which returns the sorted list of `{start, finish}` intervals currently stored that overlap the query range. Two intervals overlap if they share at least one point, so `{1, 3}` and `{3, 5}` overlap.
- `IntervalRegistry.enclosing(server, point)` which returns the sorted list of stored `{start, finish}` intervals that contain the integer `point`.
- `IntervalRegistry.stab_count(server, point)` which returns the integer number of stored intervals that contain `point`.
- `IntervalRegistry.size(server)` which returns the number of intervals currently stored.

Internally the server must keep an augmented balanced interval tree (a self-balancing BST where each node stores the maximum `finish` in its subtree) so `overlapping`, `enclosing`, and `stab_count` prune branches efficiently rather than scanning a flat list. Because ids are unique, the tree can be keyed to make `remove` an O(log n) balanced deletion. All mutations happen inside the server process, so concurrent inserts and removes from many client processes must remain consistent (the server serializes them).

Support degenerate intervals where `start == finish`. Querying an empty registry returns `[]` (or `0` for `stab_count`/`size`).

Give me the complete module in a single file. Use only the Elixir standard library, no external dependencies.