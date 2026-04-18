Write me an Elixir GenServer module called `LRUCache` that stores key-value pairs with a fixed **maximum number of entries** and evicts the **least recently used** key when the cache is full.

The motivation: TTL-based caches bound memory by time, but many workloads need memory bounded by *count* instead — a cache of the 1000 most-active users, the 500 most-recent compiled templates, etc. With no natural TTL, eviction must be driven by access recency: when a new entry is inserted and the cache is at capacity, the key that was least recently read or written is dropped.

I need these functions in the public API:

- `LRUCache.start_link(opts)` to start the process. It should accept:
  - `:name` — optional process registration name
  - `:capacity` — required positive integer, the maximum number of entries the cache will hold
  - `:clock` — zero-arity function returning an integer (any monotonically-increasing unit; only ordering matters). Defaults to `fn -> System.monotonic_time() end`. The clock is used purely to timestamp accesses for LRU ordering — there is no TTL.

- `LRUCache.put(server, key, value)` which stores a key-value pair. If the key already exists, the value is overwritten and the access timestamp is updated (so the key becomes most-recently-used). If inserting would exceed `capacity`, the single least-recently-used entry is evicted **before** the new entry is inserted. Returns `:ok`.

- `LRUCache.get(server, key)` which looks up a key. If the key exists, return `{:ok, value}` and **update the key's access timestamp to the current clock value** so it becomes most-recently-used. If the key doesn't exist, return `:miss`. A `get` that hits must therefore mutate the GenServer's state — this is unavoidable for a correct LRU.

- `LRUCache.delete(server, key)` which removes a key. Returns `:ok` whether it existed or not.

- `LRUCache.size(server)` which returns the current number of entries as a non-negative integer. Never exceeds `capacity`.

- `LRUCache.keys_by_recency(server)` which returns all keys sorted from most-recently-used to least-recently-used. Useful for debugging and testing. Returns `[]` if the cache is empty.

**Eviction semantics you must get right:**

- A `put` on a key that already exists **never evicts another key**, because the entry count doesn't change. It just updates value and timestamp.
- A `put` on a new key when `size == capacity` evicts exactly **one** entry — the one with the smallest access timestamp — before inserting.
- Both `get` (on hit) and `put` (always) count as accesses that update the timestamp.
- `delete` does not count as an access; it just removes the entry.
- `capacity` of 0 is not allowed — `start_link` should refuse it.

**Implementation note**: storing entries as `%{key => %{value, access_ts}}` and scanning for the oldest on every eviction is O(n) per eviction. That's acceptable and what I want you to do — don't bring in an ordered map or DLL. Use `Enum.min_by` on the entries when you need to evict. What matters is that the LRU semantics are correct, not that eviction is O(log n). Tie-breaking when two entries have the same access_ts (should be rare with monotonic_time) can be arbitrary; do not pretend to handle it specially.

There is no periodic sweep and no TTL — with a fixed capacity, memory is bounded by construction. Do not use `Process.send_after`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.