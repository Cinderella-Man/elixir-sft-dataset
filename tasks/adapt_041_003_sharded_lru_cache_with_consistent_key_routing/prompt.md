# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

## Existing code (your starting point)

```elixir
defmodule LRUCache do
  @moduledoc """
  A Least Recently Used (LRU) cache backed by two ETS tables.

  ## ETS tables

  Two tables are created and owned by the GenServer process:

  | Table          | Type           | Key → Value                | Purpose               |
  |----------------|----------------|----------------------------|-----------------------|
  | `<name>_data`  | `:set`         | `key → {value, timestamp}` | O(1) key lookup       |
  | `<name>_order` | `:ordered_set` | `timestamp → key`          | O(log n) LRU eviction |

  Both tables are `:named_table`s whose names are derived deterministically
  from the `:name` option, so they are stable and inspectable.  The data table
  is created `:public` with `read_concurrency: true`, so any process may read
  it directly; the order table is `:protected` – every process may read it but
  only the owning GenServer writes to it.

  ## Timestamps

  The *timestamp* is a monotonically increasing integer counter kept in the
  GenServer state – never a wall-clock value – so the cache is fully
  deterministic and testable without any clock mocking.

  The counter starts at `0`, and every touch (a `put` of a new key, an
  overwrite of a resident key, or a hit on `get`) consumes the next value by
  adding exactly `1` to it.  The first entry written to a fresh cache therefore
  carries timestamp `1`, the second `2`, and so on; the value returned for a
  touch and the counter retained in the state are always the same number.  The
  stale ordering row of a touched key is deleted as the fresh one is inserted,
  so a key is never present twice in the order table.

  ## Write serialisation

  All mutations (put, eviction, and the touch-on-get that refreshes ordering)
  are serialised through the GenServer via `GenServer.call/2`.  Reads hit ETS
  directly for maximum throughput, but still call back into the server to
  update the LRU order after a successful lookup.

  ## Example

      {:ok, _pid} = LRUCache.start_link(name: :my_cache, max_size: 3)

      :ok = LRUCache.put(:my_cache, :a, 1)
      :ok = LRUCache.put(:my_cache, :b, 2)
      :ok = LRUCache.put(:my_cache, :c, 3)

      {:ok, 1} = LRUCache.get(:my_cache, :a)   # :a is now most-recently used

      :ok = LRUCache.put(:my_cache, :d, 4)      # cache full → evicts :b (LRU)

      :miss = LRUCache.get(:my_cache, :b)
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Child spec
  # ---------------------------------------------------------------------------

  @doc false
  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type name :: atom()
  @type key :: term()
  @type value :: term()
  @type timestamp :: non_neg_integer()

  @type state :: %{
          data_table: :ets.tid(),
          order_table: :ets.tid(),
          max_size: pos_integer(),
          counter: timestamp()
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Start and link an `LRUCache` process.

  ## Options

  * `:name` (required) – atom used to register the process *and* to derive the
    names of the two backing ETS tables (`<name>_data` and `<name>_order`).
  * `:max_size` (required) – maximum number of entries the cache may hold.
    Must be a positive integer.

  The freshly started cache is empty and its timestamp counter is `0`, so the
  first entry it stores carries timestamp `1`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Look up `key` in the cache named `name`.

  Returns `{:ok, value}` on a hit and updates the entry's LRU ordering so it
  is considered most-recently used.  Returns `:miss` when the key is absent.
  """
  @spec get(name(), key()) :: {:ok, value()} | :miss
  def get(name, key) do
    data_table = data_table_name(name)

    # Read directly from ETS – no GenServer round-trip for the lookup itself.
    case :ets.lookup(data_table, key) do
      [{^key, {value, _ts}}] ->
        # Serialise the ordering update through the server.
        GenServer.call(name, {:touch, key})
        {:ok, value}

      [] ->
        :miss
    end
  end

  @doc """
  Insert or update `key` with `value` in the cache named `name`.

  * **Existing key** – value is updated and the entry is promoted to
    most-recently used.
  * **New key, cache not full** – entry is inserted.
  * **New key, cache full** – the least-recently used entry is evicted first,
    then the new entry is inserted.

  Always returns `:ok`.
  """
  @spec put(name(), key(), value()) :: :ok
  def put(name, key, value) do
    GenServer.call(name, {:put, key, value})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    max_size = Keyword.fetch!(opts, :max_size)

    unless is_integer(max_size) and max_size > 0 do
      raise ArgumentError, ":max_size must be a positive integer, got: #{inspect(max_size)}"
    end

    data_table =
      :ets.new(data_table_name(name), [
        :set,
        # allow direct reads from any process
        :public,
        :named_table,
        read_concurrency: true
      ])

    order_table =
      :ets.new(order_table_name(name), [
        :ordered_set,
        # only the owner writes; no external reads needed
        :protected,
        :named_table
      ])

    state = %{
      data_table: data_table,
      order_table: order_table,
      max_size: max_size,
      counter: 0
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:touch, key}, _from, state) do
    # Re-check: the entry might have been evicted between the ETS read and now.
    case :ets.lookup(state.data_table, key) do
      [{^key, {value, old_ts}}] ->
        {new_ts, state} = next_counter(state)
        # Remove old ordering entry, insert fresh one.
        :ets.delete(state.order_table, old_ts)
        :ets.insert(state.order_table, {new_ts, key})
        :ets.insert(state.data_table, {key, {value, new_ts}})
        {:reply, :ok, state}

      [] ->
        # Entry vanished (evicted by a concurrent put) – nothing to do.
        {:reply, :ok, state}
    end
  end

  def handle_call({:put, key, value}, _from, state) do
    state =
      case :ets.lookup(state.data_table, key) do
        [{^key, {_old_value, old_ts}}] ->
          # Key exists – update value and refresh ordering.
          {new_ts, state} = next_counter(state)
          :ets.delete(state.order_table, old_ts)
          :ets.insert(state.order_table, {new_ts, key})
          :ets.insert(state.data_table, {key, {value, new_ts}})
          state

        [] ->
          # New key – evict LRU first if we are at capacity.
          state = maybe_evict(state)
          {new_ts, state} = next_counter(state)
          :ets.insert(state.order_table, {new_ts, key})
          :ets.insert(state.data_table, {key, {value, new_ts}})
          state
      end

    {:reply, :ok, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Increment the monotonic counter and return {new_timestamp, new_state}.
  @spec next_counter(state()) :: {timestamp(), state()}
  defp next_counter(%{counter: c} = state) do
    {c + 1, %{state | counter: c + 1}}
  end

  # Evict the LRU entry when the cache is at max capacity.
  @spec maybe_evict(state()) :: state()
  defp maybe_evict(state) do
    current_size = :ets.info(state.data_table, :size)

    if current_size >= state.max_size do
      # `first/1` on an ordered_set returns the smallest key, i.e. the oldest
      # timestamp, which is exactly the least-recently used entry.
      lru_ts = :ets.first(state.order_table)
      [{^lru_ts, lru_key}] = :ets.lookup(state.order_table, lru_ts)
      :ets.delete(state.order_table, lru_ts)
      :ets.delete(state.data_table, lru_key)
    end

    state
  end

  # Derive stable, human-readable ETS table names from the cache name.
  @spec data_table_name(name()) :: atom()
  defp data_table_name(name), do: :"#{name}_data"

  @spec order_table_name(name()) :: atom()
  defp order_table_name(name), do: :"#{name}_order"
end
```

## New specification

# Design brief: `LRUCacheSharded`

## Problem

Funnelling every mutation of an LRU cache through a single GenServer creates write contention. The goal is an Elixir module called `LRUCacheSharded` that implements a **sharded** LRU cache backed by ETS, which reduces that write contention by spreading keys across several independent shard processes instead of routing every mutation through one GenServer.

## Constraints and design context

- The public façade is `LRUCacheSharded`, and internally it owns N shard GenServers, each of which is a self-contained LRU cache (with its own pair of ETS tables and its own monotonic recency counter).
- A key is always routed to the same shard via `:erlang.phash2(key, num_shards)`, and each shard enforces LRU eviction independently against a **per-shard** capacity.
- Deliver the complete module (owner plus the internal shard module) in a single file. Use only the OTP standard library — no external dependencies.

### Startup and configuration contract (constraints on construction)

- All three options are **required**; do not silently substitute defaults. A missing option must fail loudly with a `KeyError` whose `key` is the missing option name (`Keyword.fetch!/2` is the right tool) — but *where* the failure surfaces differs. `:name` is fetched in `start_link/1` itself, before the owner process is spawned, so a missing `:name` raises the `KeyError` directly in the calling process. `:num_shards` and `:max_size` are fetched during owner initialisation, so when one of those is missing `start_link` does not raise — it returns `{:error, {%KeyError{key: :num_shards}, _stacktrace}}` (or `key: :max_size`), the same linked-start failure shape as the validation errors below.
- `:num_shards` and `:max_size` must each be validated during owner initialisation as **positive integers**. Anything else (zero, negative, a float, a non-integer term) must raise `ArgumentError`. The message must contain the offending option's name written with its leading colon (the literal `:num_shards` or `:max_size`) and the received value in its `inspect/1` form (so the float `2.0` appears as `2.0`, the integer `-3` as `-3`, and the atom `:lots` as `:lots` — colon included). Because this happens inside `init/1`, the linked caller sees the start fail (an `{:error, {%ArgumentError{}, _stack}}` from `start_link`) rather than a half-built cache.
- On successful start, the owner is registered under `:name`, and it starts exactly `num_shards` shard processes, **linked** to the owner, indexed `0..num_shards - 1`. Shard names and all table names are derived deterministically from `:name` and the shard index, so a caller who knows `:name` can reason about which shard a key lives in without asking the owner.
- The owner also creates a public, named routing ETS table (name derived from `:name`) that records the shard count. This table is the single source of truth consulted by `get/2`, `put/3`, `num_shards/1`, `shard_index/2`, and `size/1` — none of those functions may issue a call into the owner process.

### Implementation requirements (constraints on internals)

- The owner process, in `init/1`, must create the public named routing ETS table recording the shard count, then start one linked shard GenServer per shard.
- Each shard owns a `:set` data table (`key → {value, timestamp}`) and an `:ordered_set` order table (`timestamp → key}`), using a monotonically increasing integer counter held in the shard's state as the timestamp — deterministic and testable without clock mocking. The counter starts at 0 and increments by one on every recency-affecting operation, so ordering is total and stable across restarts of nothing but the clock (no wall-clock reads anywhere).
- `get`/`put`/`shard_index`/`num_shards`/`size` must compute routing by reading the routing ETS table (never a call into the owner), so the owner is not a hot path.
- Each shard serialises its own writes (put, eviction, touch-on-get) through its own GenServer; reads may hit that shard's ETS table directly.
- Eviction is strictly per-shard: filling one shard beyond capacity must never evict entries that live in another shard.

## Required interface

1. `LRUCacheSharded.start_link(opts)` — accepts `:name` (required, registers the owner process and derives all table/shard names), `:num_shards` (required, a positive integer — how many shard processes to spawn), and `:max_size` (required, a positive integer — the per-shard capacity).
2. `LRUCacheSharded.get(name, key)` — returns `{:ok, value}` or `:miss`. A hit refreshes recency within that key's shard. Routing must not go through the owner process (read the routing info from ETS directly and call the correct shard), so different keys on different shards never serialise against each other.
3. `LRUCacheSharded.put(name, key, value)` — inserts/updates within the key's shard; on a full shard it evicts that shard's least-recently-used entry. Always returns `:ok`.
4. `LRUCacheSharded.num_shards(name)` — returns the configured shard count.
5. `LRUCacheSharded.shard_index(name, key)` — returns the integer shard index a key routes to (so callers/tests can reason about co-location).
6. `LRUCacheSharded.size(name)` — returns the total number of entries across all shards.
7. A `child_spec/1` so the cache can be placed directly under a supervisor: it uses `:name` as the child `id`, `:worker` type, `:permanent` restart, and a 5000 ms shutdown, with `start` being `{LRUCacheSharded, :start_link, [opts]}` (the original opts keyword list passed through unchanged).

## Acceptance criteria

### Routing

- `shard_index(name, key)` is exactly `:erlang.phash2(key, num_shards(name))`, so it is total (defined for any term), deterministic, and always in `0..num_shards - 1`. Two calls with the same key always return the same index, and any key routes to the same shard for `get`, `put`, and `shard_index` alike.
- With `num_shards: 1` the cache degenerates to a single ordinary LRU cache of capacity `max_size`; every key routes to index `0`.
- `num_shards(name)` returns the configured count for the life of the cache; it never changes.

### `get/2`

- On a miss (key never inserted, or evicted) it returns the bare atom `:miss` — not `{:error, …}`, not `nil`.
- On a hit it returns `{:ok, value}` where `value` is exactly the term that was last `put` for that key, and the hit **counts as a use**: it makes that key the most-recently-used entry *within its own shard* and therefore the last candidate for eviction there. Recency in one shard says nothing about recency in another.
- `get` may read the value straight from the shard's data table, but the recency refresh must be serialised through the shard process, so by the time `get` returns, the refresh is already visible to a subsequent `put` on the same shard.
- Repeated `get`s of the same key keep returning the same `{:ok, value}` and keep it at the most-recently-used position; `get` never mutates the size of the cache and never inserts anything on a miss.

### `put/3`

- Always returns `:ok`, whether the key was new, already present, or the shard was at capacity.
- Inserting a **new** key into a shard that already holds `max_size` entries evicts exactly one entry — that shard's least-recently-used one — before inserting, so a shard's entry count never exceeds `max_size`. The freshly inserted key is the most-recently-used entry afterwards and is never the one evicted.
- Updating an **existing** key (same key, new value) replaces the value in place, refreshes its recency to most-recently-used, and does **not** change the shard's entry count and does **not** evict anything — even when the shard is exactly at capacity.
- "Recently used" means touched by either `put/3` or a hitting `get/2`. The eviction victim is the entry whose most recent `put`/successful `get` is the oldest among that shard's entries.
- Eviction is strictly per-shard: overflowing shard *i* must never remove an entry that lives in shard *j ≠ i*. With `max_size: k` and `n` shards, the cache as a whole can hold up to `n * k` entries, but any single shard is capped at `k` regardless of how empty the others are.
- Any term is a valid key and any term is a valid value (including `nil`, tuples, and structs). Values are stored as-is and returned unchanged.

### `size/1`

- Returns the sum of the current entry counts of all shards, i.e. a `non_neg_integer()`; `0` on a freshly started cache.
- It reflects evictions: it never exceeds `num_shards * max_size`, and it stops growing once every shard is full even as more `put`s arrive.
- Overwrites of existing keys leave it unchanged.
