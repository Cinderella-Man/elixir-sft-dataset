Write me an Elixir GenServer module called `WeightedLRUCache` that implements a **cost/weight-bounded** LRU cache backed by ETS.

Unlike a plain LRU cache that caps the *number* of entries, this cache caps the *total weight* of all entries. Every entry carries an explicit integer weight (think bytes, or cost units), and the cache guarantees the sum of the weights of all resident entries never exceeds `max_weight`.

I need this public API:
- `WeightedLRUCache.start_link(opts)` — accepts `:name` (required, registers the process and names the ETS tables) and `:max_weight` (required, a positive integer — the total weight budget).
- `WeightedLRUCache.get(name, key)` — returns `{:ok, value}` or `:miss`. A hit refreshes the entry's recency.
- `WeightedLRUCache.put(name, key, value, weight)` — inserts or updates an entry with the given weight. Return values encode the failure semantics:
  - If `weight` is not a positive integer, return `{:error, :invalid_weight}` and change nothing.
  - If `weight` alone exceeds `max_weight`, the entry can never fit: return `{:error, :too_large}`, change nothing, and do **not** evict anything.
  - Otherwise return `:ok`. Before inserting, evict least-recently-used entries one at a time until the new entry fits within the budget. Updating an existing key is treated as replacing it: its old weight is released first, then it is re-inserted as the most-recently-used entry (which may itself trigger eviction of *other* entries).
- `WeightedLRUCache.weight(name)` — returns the current total resident weight.

Implementation requirements:
- Use two ETS tables owned by the GenServer: a `:set` mapping `key → {value, weight, timestamp}` for O(1) lookups, and an `:ordered_set` mapping `timestamp → key` to find the LRU entry for eviction.
- Use a monotonically increasing integer counter in the GenServer state as the timestamp, so recency ordering is deterministic and testable without clock mocking.
- Track the running total weight in the GenServer state and keep it exactly in sync as entries are inserted, updated, and evicted.
- All mutations (put, eviction, touch-on-get) go through the GenServer to serialise writes; reads may hit ETS directly.
- Eviction removes whole entries (never partial). A single `put` may evict several entries in a row to make room. There is no TTL or background cleanup.

Give me the complete module in a single file. Use only the OTP standard library — no external dependencies.