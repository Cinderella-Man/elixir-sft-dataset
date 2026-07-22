# Priority-Resolved BiMap

Write me an Elixir GenServer module called `PriorityBiMap` that maintains a **bidirectional mapping** (a bijection between keys and values) where every pair carries a **priority**, and conflicts are resolved by priority rather than by last-write-wins. Unlike a classic BiMap — where a new `put` always evicts whatever collides with it — here a lower-priority write is **rejected** and leaves the existing mappings untouched.

## Public API

- `PriorityBiMap.start_link(opts)` — starts the process. It must accept a `:name` option used to register the process (all other functions take that name — or any valid GenServer server reference — as their first argument). Return the usual `{:ok, pid}`.

- `PriorityBiMap.put(name, key, value, priority)` — attempts to install the association `{key, value}` with the given integer `priority`. A `put` can conflict with **up to two** existing pairs: the pair currently at `key` (if `key` maps to a *different* value) and the pair currently at `value` (if `value` maps to a *different* key). Resolution:
  - **Same pair already present** (`key` already maps to exactly `value`): accept and update the stored priority to `priority`. Returns `{:ok, []}` (nothing displaced).
  - **No conflict** (both `key` and `value` are free): install the pair. Returns `{:ok, []}`.
  - **Conflict(s) exist**: the new pair is accepted **only if `priority` is strictly greater than every conflicting pair's priority**. On acceptance, all conflicting pairs are evicted and the new pair installed; returns `{:ok, evicted}` where `evicted` is the list of displaced `{key, value}` pairs. If `priority` is **not** strictly greater than some conflicting pair (including ties), the put is **rejected**: nothing changes and it returns `{:error, :rejected}`.

- `PriorityBiMap.get_by_key(name, key)` — returns `{:ok, value}` if `key` is present, otherwise `:error`.

- `PriorityBiMap.get_by_value(name, value)` — returns `{:ok, key}` if `value` is present, otherwise `:error`.

- `PriorityBiMap.priority(name, key)` — returns `{:ok, priority}` for the pair at `key`, otherwise `:error`.

- `PriorityBiMap.delete(name, key)` — removes `key` and its associated value (both directions), including its priority. Returns `:ok`. Deleting an absent key is a harmless no-op.

## The invariant

- The structure is always a true bijection: every `get_by_key(name, k)` returning `{:ok, v}` implies `get_by_value(name, v)` returns `{:ok, k}`, and vice versa; each key/value is associated with at most one partner.
- A rejected `put` is a complete no-op: no mapping, no priority, no partial change.
- An accepted conflicting `put` evicts every conflicting pair (both the key-side and the value-side pair when they differ) so the bijection is preserved, and reports exactly those displaced pairs.

Keys and values can be any term (priorities are integers). Use only the OTP standard library — no external dependencies. Give me the complete module in a single file.