# Bidirectional Map GenServer

Write me an Elixir GenServer module called `BiMap` that maintains a **bidirectional mapping** between keys and values. Every key maps to exactly one value, and every value maps back to exactly one key — the mapping is always a bijection.

## Public API

- `BiMap.start_link(opts)` — starts the process. It must accept a `:name` option used to register the process (all other functions take that name — or any valid GenServer server reference — as their first argument). Return the usual `{:ok, pid}`.

- `BiMap.put(name, key, value)` — inserts or updates the association between `key` and `value`. Always returns `:ok`. This is where the bijection invariant must be enforced:
  - If `key` is already associated with a *different* value, the old value's reverse mapping must be removed before the new one is installed.
  - If `value` is already associated with a *different* key, that old key's mapping must be removed (so the value now points to the new key).
  - Putting the exact same `{key, value}` pair again is a no-op that leaves the pair intact.

- `BiMap.get_by_key(name, key)` — returns `{:ok, value}` if `key` is present, otherwise `:error`.

- `BiMap.get_by_value(name, value)` — returns `{:ok, key}` if `value` is present, otherwise `:error`.

- `BiMap.delete(name, key)` — removes `key` and its associated value (both directions). Returns `:ok`. Deleting a key that isn't present is a harmless no-op that still returns `:ok`.

## The invariant

At all times the structure must remain a true bijection: there is never a forward entry `key → value` without the matching reverse entry `value → key`, and no value or key is ever associated with more than one partner. Concretely, after any sequence of `put`/`delete` calls:

- Every `get_by_key(name, k)` that returns `{:ok, v}` implies `get_by_value(name, v)` returns `{:ok, k}`, and vice versa.
- Reassigning a key to a new value must orphan the old value (its `get_by_value` becomes `:error`).
- Reassigning a value to a new key must orphan the old key (its `get_by_key` becomes `:error`).

Keys and values can be any term (atoms, integers, strings, tuples, etc.).

Give me the complete module in a single file. Use only the OTP standard library — no external dependencies.