Write me an Elixir module called `LRUCacheSharded` that implements a **sharded** LRU cache backed by ETS, designed to reduce write contention by spreading keys across several independent shard processes instead of funnelling every mutation through a single GenServer.

The public façade is `LRUCacheSharded`, and internally it owns N shard GenServers, each of which is a self-contained LRU cache (with its own pair of ETS tables and its own monotonic recency counter). A key is always routed to the same shard via `:erlang.phash2(key, num_shards)`, and each shard enforces LRU eviction independently against a **per-shard** capacity.

I need this public API:
- `LRUCacheSharded.start_link(opts)` — accepts `:name` (required, registers the owner process and derives all table/shard names), `:num_shards` (required, a positive integer — how many shard processes to spawn), and `:max_size` (required, a positive integer — the per-shard capacity).
- `LRUCacheSharded.get(name, key)` — returns `{:ok, value}` or `:miss`. A hit refreshes recency within that key's shard. Routing must not go through the owner process (read the routing info from ETS directly and call the correct shard), so different keys on different shards never serialise against each other.
- `LRUCacheSharded.put(name, key, value)` — inserts/updates within the key's shard; on a full shard it evicts that shard's least-recently-used entry. Always returns `:ok`.
- `LRUCacheSharded.num_shards(name)` — returns the configured shard count.
- `LRUCacheSharded.shard_index(name, key)` — returns the integer shard index a key routes to (so callers/tests can reason about co-location).
- `LRUCacheSharded.size(name)` — returns the total number of entries across all shards.

Implementation requirements:
- The owner process, in `init/1`, must create a public named routing ETS table recording the shard count, then start one linked shard GenServer per shard. Each shard owns a `:set` data table (`key → {value, timestamp}`) and an `:ordered_set` order table (`timestamp → key`), using a monotonically increasing integer counter in its state as the timestamp — deterministic and testable without clock mocking.
- `get`/`put`/`shard_index`/`num_shards`/`size` must compute routing by reading the routing ETS table (never a call into the owner), so the owner is not a hot path.
- Each shard serialises its own writes (put, eviction, touch-on-get) through its own GenServer; reads may hit that shard's ETS table directly.
- Eviction is strictly per-shard: filling one shard beyond capacity must never evict entries that live in another shard.

Give me the complete module (owner plus the internal shard module) in a single file. Use only the OTP standard library — no external dependencies.