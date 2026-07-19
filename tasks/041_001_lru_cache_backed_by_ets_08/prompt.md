# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `init` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `LRUCache` that implements a Least Recently Used cache backed by ETS.

## Public API

- `LRUCache.start_link(opts)` — start and link the process. Options:
  - `:name` (required, atom) — used both to register the GenServer process under that name and to derive the names of the backing ETS tables. There are no defaults for either option; both must be supplied by the caller.
  - `:max_size` (required) — the maximum number of entries the cache may hold at once. Must be a positive integer; if it is missing, not an integer, or is zero or negative, starting the cache must fail (raise `ArgumentError` from the process's initialisation for a bad value, and a `KeyError`-style failure for a missing key). A `max_size` of `1` is legal and means every insert of a new key evicts the only resident entry.
  - Returns the usual `GenServer.on_start()` shape (`{:ok, pid}` on success).
- `LRUCache.get(name, key)` — look up `key` in the cache registered under `name`.
  - Returns `{:ok, value}` when the key is present. The value returned is whatever was last `put` for that key, including values like `nil` or `false` — presence is decided by the key existing, never by the value being truthy.
  - Returns the bare atom `:miss` when the key is absent. `:miss` is the *only* miss shape; it is not `{:error, …}` and not `nil`.
  - A hit promotes the entry to most-recently-used before returning, so it is evicted only after every entry that has not been touched since. A miss changes nothing — it must not create an entry, must not evict anything, and must not disturb the ordering of any other key.
  - Repeated `get`s on the same key each re-promote it; the entry stays the newest as long as it keeps being read.
- `LRUCache.put(name, key, value)` — insert or update an entry. Always returns `:ok`, in every case below.
  - **Existing key**: the stored value is replaced with `value` and the entry is promoted to most-recently-used. The cache size is unchanged, and no eviction happens — even when the cache is exactly at `max_size`. Overwriting a key never evicts.
  - **New key, cache below `max_size`**: the entry is inserted and becomes most-recently-used. Size grows by one.
  - **New key, cache exactly at `max_size`**: the single least-recently-used entry is evicted *first*, then the new entry is inserted. Size stays at `max_size` — it never exceeds it, and exactly one entry leaves per insert-at-capacity. A subsequent `get` on the evicted key returns `:miss`.

Keys and values may be any term.

## Recency semantics

"Recently used" is defined by both `put` and a *successful* `get`: each of those makes the touched key the most-recently-used entry, and the entry evicted at capacity is always the one whose last successful `put`/`get` is oldest. A `get` that misses does not count as a use of anything. Ordering is total and deterministic: for any two resident keys, exactly one is more recently used, decided by which was touched last.

## Implementation requirements

- Use two ETS tables owned by the GenServer, named deterministically from the `:name` option so they are stable and inspectable — both must be `:named_table`s. The first is a `:set` table `:"<name>_data"` mapping `key → {value, timestamp}` for O(1) lookups; create it `:public` with `read_concurrency: true` so any process may read it directly. The second is an `:ordered_set` table `:"<name>_order"` mapping `timestamp → key` so the least-recently-used entry is found in O(log n); create it `:protected` so any process may read it but only the owner writes to it.
- Use a monotonically increasing integer counter held in the GenServer state as the "timestamp" — never a wall-clock value — so ordering is deterministic and the cache is testable without any clock mocking. The counter starts at `0`, and every touch (put of a new key, overwrite, hit-on-get) adds exactly `1` to it and stamps the touched key with that value: the first key written to a fresh cache carries timestamp `1`, the next `2`, and so on in an unbroken sequence, and the number stored alongside a key in the data table is exactly this counter value. A miss consumes no counter value. The stale ordering entry for a touched key is removed as the fresh one is inserted, so a key is never present twice in the order table.
- All mutations — `put`, eviction, and the touch-on-get that refreshes ordering — must be serialised through the GenServer (a synchronous call), so that when `put/3` returns `:ok` the write is already visible, and when `get/2` returns `{:ok, value}` the promotion has already been applied. Reads may hit ETS directly for throughput.
- Because a direct ETS read can race with a concurrent eviction, the touch path must tolerate the key having disappeared between the read and the ordering update: in that case it simply does nothing and the caller still gets its `{:ok, value}`. The server must never crash on this race.
- Provide a `child_spec/1` so the cache can be placed under a supervisor, using the `:name` option as the child `id`.
- There is no TTL and no background cleanup: entries only ever leave the cache through LRU eviction, and the process holds its entries for as long as it lives. Nothing is persisted across a restart.

Give me the complete module in a single file. Use only the OTP standard library — no external dependencies.

## The module with `init` missing

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

  def init(opts) do
    # TODO
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

Give me only the complete implementation of `init` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
