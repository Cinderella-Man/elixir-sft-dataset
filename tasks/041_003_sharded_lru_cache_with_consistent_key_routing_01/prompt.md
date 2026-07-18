Write me an Elixir module called `LRUCacheSharded` that implements a **sharded** LRU cache backed by ETS, designed to reduce write contention by spreading keys across several independent shard processes instead of funnelling every mutation through a single GenServer.

The public façade is `LRUCacheSharded`, and internally it owns N shard GenServers, each of which is a self-contained LRU cache (with its own pair of ETS tables and its own monotonic recency counter). A key is always routed to the same shard via `:erlang.phash2(key, num_shards)`, and each shard enforces LRU eviction independently against a **per-shard** capacity.

## Public API

- `LRUCacheSharded.start_link(opts)` — accepts `:name` (required, registers the owner process and derives all table/shard names), `:num_shards` (required, a positive integer — how many shard processes to spawn), and `:max_size` (required, a positive integer — the per-shard capacity).
- `LRUCacheSharded.get(name, key)` — returns `{:ok, value}` or `:miss`. A hit refreshes recency within that key's shard. Routing must not go through the owner process (read the routing info from ETS directly and call the correct shard), so different keys on different shards never serialise against each other.
- `LRUCacheSharded.put(name, key, value)` — inserts/updates within the key's shard; on a full shard it evicts that shard's least-recently-used entry. Always returns `:ok`.
- `LRUCacheSharded.num_shards(name)` — returns the configured shard count.
- `LRUCacheSharded.shard_index(name, key)` — returns the integer shard index a key routes to (so callers/tests can reason about co-location).
- `LRUCacheSharded.size(name)` — returns the total number of entries across all shards.

## Startup and configuration contract

- All three options are **required**; do not silently substitute defaults. A missing option must fail loudly with a `KeyError` whose `key` is the missing option name (`Keyword.fetch!/2` is the right tool) — but *where* the failure surfaces differs. `:name` is fetched in `start_link/1` itself, before the owner process is spawned, so a missing `:name` raises the `KeyError` directly in the calling process. `:num_shards` and `:max_size` are fetched during owner initialisation, so when one of those is missing `start_link` does not raise — it returns `{:error, {%KeyError{key: :num_shards}, _stacktrace}}` (or `key: :max_size`), the same linked-start failure shape as the validation errors below.
- `:num_shards` and `:max_size` must each be validated during owner initialisation as **positive integers**. Anything else (zero, negative, a float, a non-integer term) must raise `ArgumentError`. The message must contain the offending option's name written with its leading colon (the literal `:num_shards` or `:max_size`) and the received value in its `inspect/1` form (so the float `2.0` appears as `2.0`, the integer `-3` as `-3`, and the atom `:lots` as `:lots` — colon included). Because this happens inside `init/1`, the linked caller sees the start fail (an `{:error, {%ArgumentError{}, _stack}}` from `start_link`) rather than a half-built cache.
- On successful start, the owner is registered under `:name`, and it starts exactly `num_shards` shard processes, **linked** to the owner, indexed `0..num_shards - 1`. Shard names and all table names are derived deterministically from `:name` and the shard index, so a caller who knows `:name` can reason about which shard a key lives in without asking the owner.
- The owner also creates a public, named routing ETS table (name derived from `:name`) that records the shard count. This table is the single source of truth consulted by `get/2`, `put/3`, `num_shards/1`, `shard_index/2`, and `size/1` — none of those functions may issue a call into the owner process.
- The module also exposes a `child_spec/1` so the cache can be placed directly under a supervisor: it uses `:name` as the child `id`, `:worker` type, `:permanent` restart, and a 5000 ms shutdown, with `start` being `{LRUCacheSharded, :start_link, [opts]}` (the original opts keyword list passed through unchanged).

## Observable behavior

**Routing**
- `shard_index(name, key)` is exactly `:erlang.phash2(key, num_shards(name))`, so it is total (defined for any term), deterministic, and always in `0..num_shards - 1`. Two calls with the same key always return the same index, and any key routes to the same shard for `get`, `put`, and `shard_index` alike.
- With `num_shards: 1` the cache degenerates to a single ordinary LRU cache of capacity `max_size`; every key routes to index `0`.
- `num_shards(name)` returns the configured count for the life of the cache; it never changes.

**`get/2`**
- On a miss (key never inserted, or evicted) it returns the bare atom `:miss` — not `{:error, …}`, not `nil`.
- On a hit it returns `{:ok, value}` where `value` is exactly the term that was last `put` for that key, and the hit **counts as a use**: it makes that key the most-recently-used entry *within its own shard* and therefore the last candidate for eviction there. Recency in one shard says nothing about recency in another.
- `get` may read the value straight from the shard's data table, but the recency refresh must be serialised through the shard process, so by the time `get` returns, the refresh is already visible to a subsequent `put` on the same shard.
- Repeated `get`s of the same key keep returning the same `{:ok, value}` and keep it at the most-recently-used position; `get` never mutates the size of the cache and never inserts anything on a miss.

**`put/3`**
- Always returns `:ok`, whether the key was new, already present, or the shard was at capacity.
- Inserting a **new** key into a shard that already holds `max_size` entries evicts exactly one entry — that shard's least-recently-used one — before inserting, so a shard's entry count never exceeds `max_size`. The freshly inserted key is the most-recently-used entry afterwards and is never the one evicted.
- Updating an **existing** key (same key, new value) replaces the value in place, refreshes its recency to most-recently-used, and does **not** change the shard's entry count and does **not** evict anything — even when the shard is exactly at capacity.
- "Recently used" means touched by either `put/3` or a hitting `get/2`. The eviction victim is the entry whose most recent `put`/successful `get` is the oldest among that shard's entries.
- Eviction is strictly per-shard: overflowing shard *i* must never remove an entry that lives in shard *j ≠ i*. With `max_size: k` and `n` shards, the cache as a whole can hold up to `n * k` entries, but any single shard is capped at `k` regardless of how empty the others are.
- Any term is a valid key and any term is a valid value (including `nil`, tuples, and structs). Values are stored as-is and returned unchanged.

**`size/1`**
- Returns the sum of the current entry counts of all shards, i.e. a `non_neg_integer()`; `0` on a freshly started cache.
- It reflects evictions: it never exceeds `num_shards * max_size`, and it stops growing once every shard is full even as more `put`s arrive.
- Overwrites of existing keys leave it unchanged.

## Implementation requirements

- The owner process, in `init/1`, must create the public named routing ETS table recording the shard count, then start one linked shard GenServer per shard.
- Each shard owns a `:set` data table (`key → {value, timestamp}`) and an `:ordered_set` order table (`timestamp → key}`), using a monotonically increasing integer counter held in the shard's state as the timestamp — deterministic and testable without clock mocking. The counter starts at 0 and increments by one on every recency-affecting operation, so ordering is total and stable across restarts of nothing but the clock (no wall-clock reads anywhere).
- `get`/`put`/`shard_index`/`num_shards`/`size` must compute routing by reading the routing ETS table (never a call into the owner), so the owner is not a hot path.
- Each shard serialises its own writes (put, eviction, touch-on-get) through its own GenServer; reads may hit that shard's ETS table directly.
- Eviction is strictly per-shard: filling one shard beyond capacity must never evict entries that live in another shard.

Give me the complete module (owner plus the internal shard module) in a single file. Use only the OTP standard library — no external dependencies.
