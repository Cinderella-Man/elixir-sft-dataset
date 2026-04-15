Write me an Elixir GenServer module called `LRUCache` that implements a Least Recently Used cache backed by ETS.

I need these functions in the public API:
- `LRUCache.start_link(opts)` to start the process. It should accept a `:name` option (required) used both to register the process and to name the ETS tables, and a `:max_size` option (required) that caps how many entries the cache may hold at once.
- `LRUCache.get(name, key)` which looks up a key. Return `{:ok, value}` if the key exists, or `:miss` if it does not. A successful get must update the entry's "last used" ordering so it is not evicted before more stale entries.
- `LRUCache.put(name, key, value)` which inserts or updates an entry. If the key already exists, update its value and refresh its "last used" ordering. If the cache is already at `max_size` and the key is new, evict the least recently used entry before inserting. Always return `:ok`.

Implementation requirements:
- Use two ETS tables owned by the GenServer: one that maps `key → {value, timestamp}` for O(1) lookups, and one ordered set that maps `timestamp → key` to efficiently find the LRU entry for eviction.
- Use a monotonically increasing counter (a simple integer you increment in state) as the "timestamp" so that ordering is always deterministic regardless of wall-clock time — this makes the cache fully testable without any clock mocking.
- All mutations (`put`, eviction, touch-on-get) must go through the GenServer process to serialise writes; reads (`get`) may either go through the GenServer or read directly from ETS — your choice.
- There is no TTL or background cleanup; entries only leave the cache through LRU eviction.

Give me the complete module in a single file. Use only the OTP standard library — no external dependencies.