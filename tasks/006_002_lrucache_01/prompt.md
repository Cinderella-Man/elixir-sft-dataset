**Ticket: Implement `LRUCache` — count-bounded GenServer cache with LRU eviction**

Build an Elixir GenServer module `LRUCache` storing key-value pairs with a fixed **maximum number of entries**, evicting the **least recently used** key when full. Single file, OTP standard library only, no external dependencies.

**Context / rationale**
- TTL-based caches bound memory by time; this cache bounds memory by *count* instead (e.g. the 1000 most-active users, the 500 most-recent compiled templates).
- With no natural TTL, eviction is driven by access recency: when a new entry is inserted and the cache is at capacity, the key least recently read or written is dropped.

**Public API**
- `LRUCache.start_link(opts)` — start the process. Accepts:
  - `:name` — optional process registration name.
  - `:capacity` — required positive integer, the maximum number of entries the cache will hold.
  - `:clock` — zero-arity function returning an integer (any monotonically-increasing unit; only ordering matters). Defaults to `fn -> System.monotonic_time() end`. Used purely to timestamp accesses for LRU ordering — there is no TTL.
- `LRUCache.put(server, key, value)` — stores a key-value pair. If the key already exists, overwrite the value and update the access timestamp (key becomes most-recently-used). If inserting would exceed `capacity`, evict the single least-recently-used entry **before** inserting the new entry. Returns `:ok`.
- `LRUCache.get(server, key)` — lookup. On hit, return `{:ok, value}` and **update the key's access timestamp to the current clock value** (becomes most-recently-used). On miss, return `:miss`. A `get` that hits must mutate the GenServer's state — unavoidable for a correct LRU.
- `LRUCache.delete(server, key)` — removes a key. Returns `:ok` whether it existed or not.
- `LRUCache.size(server)` — returns the current number of entries as a non-negative integer. Never exceeds `capacity`.
- `LRUCache.keys_by_recency(server)` — returns all keys sorted most-recently-used to least-recently-used. Returns `[]` if the cache is empty. (For debugging and testing.)

**Eviction semantics**
- A `put` on an existing key **never evicts** another key — the entry count doesn't change; it only updates value and timestamp.
- A `put` on a new key when `size == capacity` evicts exactly **one** entry — the one with the smallest access timestamp — before inserting.
- Both `get` (on hit) and `put` (always) count as accesses that update the timestamp.
- `delete` does not count as an access; it just removes the entry.
- `capacity` of 0 is not allowed — `start_link` must refuse it.

**Implementation constraints**
- Store entries as `%{key => %{value, access_ts}}` and scan for the oldest on every eviction — O(n) per eviction is acceptable and required. Do not bring in an ordered map or DLL. Use `Enum.min_by` on the entries when you need to evict.
- What matters is correct LRU semantics, not O(log n) eviction.
- Tie-breaking when two entries share the same access_ts (rare with monotonic_time) may be arbitrary; do not pretend to handle it specially.
- No periodic sweep and no TTL — with a fixed capacity, memory is bounded by construction. Do not use `Process.send_after`.

**Input validation contract**
- When `:capacity` is not a positive integer (e.g. `0` or `-1`), `start_link/1` raises `ArgumentError` in the calling process. Validate the option in `start_link/1` itself, before starting the GenServer — a failure inside `init/1` would surface to the caller as an exit, not a raise.

**Deliverable**
- The complete module in a single file.
