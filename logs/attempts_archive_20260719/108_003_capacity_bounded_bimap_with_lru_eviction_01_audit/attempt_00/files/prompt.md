# Capacity-Bounded BiMap with LRU Eviction

Write me an Elixir GenServer module called `BoundedBiMap` that maintains a **bidirectional mapping** (a bijection between keys and values, exactly like a classic BiMap) but with a **fixed maximum number of pairs** enforced by **least-recently-used (LRU) eviction**. Memory is bounded by construction: once the map is full, inserting a brand-new key evicts the least-recently-used pair to make room.

## Public API

- `BoundedBiMap.start_link(opts)` — starts the process. It must accept a `:name` option used to register the process and a required `:capacity` option (a positive integer, the maximum number of pairs). All other functions take the name (or any valid GenServer server reference) as their first argument. Return the usual `{:ok, pid}`.

- `BoundedBiMap.put(name, key, value)` — inserts or updates the association between `key` and `value`, preserving the bijection. Always returns `:ok`. A `put` counts as **using** the pair (it refreshes recency). Eviction rules:
  - If `key` already maps to a different value, the old value's reverse mapping is removed (standard bijection maintenance) — this is an *update*, not a new key, so it never triggers LRU eviction.
  - If `value` already maps to a different key, that old key is removed entirely (bijection maintenance). This frees a slot, so it may make room without any LRU eviction.
  - If, after the above maintenance, `key` is a **brand-new key** and the map is already at `capacity`, evict the least-recently-used pair (both directions) before installing the new pair.

- `BoundedBiMap.get_by_key(name, key)` — returns `{:ok, value}` if `key` is present, otherwise `:error`. A successful lookup counts as **using** the pair (it refreshes recency, protecting it from the next eviction).

- `BoundedBiMap.get_by_value(name, value)` — returns `{:ok, key}` if `value` is present, otherwise `:error`. A successful lookup also refreshes the pair's recency.

- `BoundedBiMap.delete(name, key)` — removes `key` and its associated value (both directions), freeing a slot. Returns `:ok`. Deleting an absent key is a harmless no-op.

- `BoundedBiMap.size(name)` — returns the current number of pairs.

- `BoundedBiMap.keys_by_recency(name)` — returns the current keys as a list ordered least-recently-used first, most-recently-used last (useful for inspecting the eviction order).

## Semantics

- The structure is always a true bijection: every `get_by_key(name, k)` returning `{:ok, v}` implies `get_by_value(name, v)` returns `{:ok, k}`, and vice versa.
- The number of pairs never exceeds `capacity`.
- Recency is refreshed by **every** `put` and by **every successful** `get_by_key`/`get_by_value`. Overwriting an existing key updates its value and refreshes recency but does **not** change the count, so it never evicts another pair.
- When a new-key insertion at capacity requires eviction, exactly the least-recently-used pair is removed.

Keys and values can be any term. Use only the OTP standard library — no external dependencies. Give me the complete module in a single file.