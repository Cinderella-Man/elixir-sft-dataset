# Design Brief: `LRUCache`

## Problem

Build an Elixir GenServer module called `LRUCache` that implements a Least Recently Used cache backed by ETS. Deliver the complete module in a single file, using only the OTP standard library — no external dependencies.

## Constraints & Semantics

**Storage architecture.** The cache uses two ETS tables owned by the GenServer, named deterministically from the `:name` option so they are stable and inspectable — both must be `:named_table`s:

- The first is a `:set` table `:"<name>_data"` mapping `key → {value, timestamp}` for O(1) lookups; create it `:public` with `read_concurrency: true` so any process may read it directly.
- The second is an `:ordered_set` table `:"<name>_order"` mapping `timestamp → key` so the least-recently-used entry is found in O(log n); create it `:protected` so any process may read it but only the owner writes to it.

**Timestamp counter.** Use a monotonically increasing integer counter held in the GenServer state as the "timestamp" — never a wall-clock value — so ordering is deterministic and the cache is testable without any clock mocking. The counter starts at `0`, and every touch (put of a new key, overwrite, hit-on-get) adds exactly `1` to it and stamps the touched key with that value: the first key written to a fresh cache carries timestamp `1`, the next `2`, and so on in an unbroken sequence, and the number stored alongside a key in the data table is exactly this counter value. A miss consumes no counter value. The stale ordering entry for a touched key is removed as the fresh one is inserted, so a key is never present twice in the order table.

**Recency definition.** "Recently used" is defined by both `put` and a *successful* `get`: each of those makes the touched key the most-recently-used entry, and the entry evicted at capacity is always the one whose last successful `put`/`get` is oldest. A `get` that misses does not count as a use of anything. Ordering is total and deterministic: for any two resident keys, exactly one is more recently used, decided by which was touched last.

**Concurrency & serialisation.** All mutations — `put`, eviction, and the touch-on-get that refreshes ordering — must be serialised through the GenServer (a synchronous call), so that when `put/3` returns `:ok` the write is already visible, and when `get/2` returns `{:ok, value}` the promotion has already been applied. Reads may hit ETS directly for throughput. Because a direct ETS read can race with a concurrent eviction, the touch path must tolerate the key having disappeared between the read and the ordering update: in that case it simply does nothing and the caller still gets its `{:ok, value}`. The server must never crash on this race.

**Lifecycle.** There is no TTL and no background cleanup: entries only ever leave the cache through LRU eviction, and the process holds its entries for as long as it lives. Nothing is persisted across a restart. Keys and values may be any term.

## Required Interface

1. `LRUCache.start_link(opts)` — start and link the process. Returns the usual `GenServer.on_start()` shape (`{:ok, pid}` on success). Options:
   1. `:name` (required, atom) — used both to register the GenServer process under that name and to derive the names of the backing ETS tables. There are no defaults for either option; both must be supplied by the caller.
   2. `:max_size` (required) — the maximum number of entries the cache may hold at once. Must be a positive integer; if it is missing, not an integer, or is zero or negative, starting the cache must fail (raise `ArgumentError` from the process's initialisation for a bad value, and a `KeyError`-style failure for a missing key). A `max_size` of `1` is legal and means every insert of a new key evicts the only resident entry.

2. `LRUCache.get(name, key)` — look up `key` in the cache registered under `name`.
   1. Returns `{:ok, value}` when the key is present. The value returned is whatever was last `put` for that key, including values like `nil` or `false` — presence is decided by the key existing, never by the value being truthy.
   2. Returns the bare atom `:miss` when the key is absent. `:miss` is the *only* miss shape; it is not `{:error, …}` and not `nil`.
   3. A hit promotes the entry to most-recently-used before returning, so it is evicted only after every entry that has not been touched since. A miss changes nothing — it must not create an entry, must not evict anything, and must not disturb the ordering of any other key.
   4. Repeated `get`s on the same key each re-promote it; the entry stays the newest as long as it keeps being read.

3. `LRUCache.put(name, key, value)` — insert or update an entry. Always returns `:ok`, in every case below.
   1. **Existing key**: the stored value is replaced with `value` and the entry is promoted to most-recently-used. The cache size is unchanged, and no eviction happens — even when the cache is exactly at `max_size`. Overwriting a key never evicts.
   2. **New key, cache below `max_size`**: the entry is inserted and becomes most-recently-used. Size grows by one.
   3. **New key, cache exactly at `max_size`**: the single least-recently-used entry is evicted *first*, then the new entry is inserted. Size stays at `max_size` — it never exceeds it, and exactly one entry leaves per insert-at-capacity. A subsequent `get` on the evicted key returns `:miss`.

4. `child_spec/1` — provide it so the cache can be placed under a supervisor, using the `:name` option as the child `id`.

## Acceptance Criteria

- The complete module `LRUCache` is delivered in a single file, using only the OTP standard library with no external dependencies.
- `start_link/1` registers the process under `:name`, derives both ETS table names from it, and rejects a bad `:max_size` by raising `ArgumentError` from init and a `KeyError`-style failure when `:max_size` is missing; `max_size` of `1` evicts the sole resident on each new-key insert.
- `get/2` returns `{:ok, value}` on presence (including `nil`/`false` values), `:miss` on absence, promotes on a hit, and leaves everything untouched on a miss; repeated hits keep re-promoting.
- `put/3` always returns `:ok`; overwrites replace-and-promote without ever evicting; new-key inserts below capacity grow size by one; new-key inserts at `max_size` evict the LRU entry first, keep size at `max_size`, and make the evicted key return `:miss`.
- Two `:named_table` ETS tables exist: `:"<name>_data"` as a `:public` `:set` with `read_concurrency: true` storing `key → {value, timestamp}`, and `:"<name>_order"` as a `:protected` `:ordered_set` storing `timestamp → key`.
- The state counter starts at `0`, increments by exactly `1` per touch (new-key put, overwrite, hit-on-get) and stamps the touched key with that value (first key → `1`, next → `2`, unbroken); a miss consumes no counter value; the stale order entry is removed as the fresh one is inserted so no key appears twice in the order table.
- Eviction always targets the entry whose last successful `put`/`get` is oldest; ordering is total and deterministic.
- All mutations are serialised through a synchronous GenServer call so a returned `:ok` from `put/3` means the write is visible and a returned `{:ok, value}` from `get/2` means the promotion is applied; reads may hit ETS directly.
- The touch path tolerates a key disappearing between the direct read and the ordering update — it does nothing in that case, still returns `{:ok, value}`, and never crashes the server.
- No TTL or background cleanup exists; entries leave only via LRU eviction, persist for the process lifetime, and are not persisted across a restart. Keys and values may be any term.
