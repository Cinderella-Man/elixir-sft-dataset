# Bidirectional Multimap (Many-to-Many) GenServer

Write me an Elixir GenServer module called `BiMultiMap` that maintains a **bidirectional many-to-many relation** between keys and values. Unlike a strict bijection, a single key may be associated with *many* values, and a single value may be associated with *many* keys. What must always hold is that the forward and reverse indexes agree perfectly: an association `key ↔ value` is either present in both directions or absent from both.

## Public API

- `BiMultiMap.start_link(opts)` — starts the process. It must accept a `:name` option used to register the process (all other functions take that name — or any valid GenServer server reference — as their first argument). Return the usual `{:ok, pid}`.

- `BiMultiMap.put(name, key, value)` — records the association between `key` and `value`. Always returns `:ok`. Adding the same `{key, value}` pair again is an idempotent no-op (the relation is a *set* of pairs, never a multiset). A key may accumulate several values and a value may accumulate several keys.

- `BiMultiMap.member?(name, key, value)` — returns `true` if the association `{key, value}` is currently present, otherwise `false`.

- `BiMultiMap.get_by_key(name, key)` — returns a `MapSet` of all values currently associated with `key` (an **empty `MapSet`** if the key has none).

- `BiMultiMap.get_by_value(name, value)` — returns a `MapSet` of all keys currently associated with `value` (an **empty `MapSet`** if the value has none).

- `BiMultiMap.delete(name, key, value)` — removes the single association `{key, value}` in both directions. Returns `:ok`. Removing an association that isn't present is a harmless no-op.

- `BiMultiMap.delete_key(name, key)` — removes `key` and *all* of its associations, cleaning up the reverse index for every value that was attached to it. Returns `:ok`.

- `BiMultiMap.delete_value(name, value)` — removes `value` and *all* of its associations, cleaning up the forward index for every key that was attached to it. Returns `:ok`.

## The invariant

At all times the forward and reverse indexes must stay consistent:

- `member?(name, k, v)` is `true` **iff** `v` is in `get_by_key(name, k)` **iff** `k` is in `get_by_value(name, v)`.
- When the last value is removed from a key (via `delete/3`, `delete_value/2`, etc.), that key must disappear entirely from the forward index — `get_by_key` returns an empty `MapSet` and the internal map no longer holds a stale empty set. The symmetric rule holds for values in the reverse index.

Keys and values can be any term (atoms, integers, strings, tuples, etc.).

Give me the complete module in a single file. Use only the OTP standard library — no external dependencies.