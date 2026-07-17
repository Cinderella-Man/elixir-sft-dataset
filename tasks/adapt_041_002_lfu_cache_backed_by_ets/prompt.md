# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

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

Write me an Elixir GenServer module called `LFUCache` that implements a **Least Frequently Used** cache backed by ETS.

Unlike an LRU cache (which evicts the entry that was accessed least recently), this cache evicts the entry that has been accessed the *fewest times*. When two entries are tied on access frequency, break the tie by evicting the one that is least recently used among them.

## Public API

- `LFUCache.start_link(opts)` to start the process. It should accept a `:name` option (required) used both to register the process and to name the ETS tables, and a `:max_size` option (required) that caps how many entries the cache may hold at once.
- `LFUCache.get(name, key)` which looks up a key. Return `{:ok, value}` if the key exists, or `:miss` if it does not. A successful get counts as one access and must increment that entry's frequency.
- `LFUCache.put(name, key, value)` which inserts or updates an entry. A brand-new entry starts with a frequency of 1. If the key already exists, update its value and count the write as an access (increment its frequency). If the cache is already at `max_size` and the key is new, evict the least frequently used entry (tie broken by least recently used) before inserting. Always return `:ok`.

## Behaviour contract

### `start_link/1`

- `:name` is required and is an atom. It registers the GenServer under that name, so every later call takes the same atom as its first argument. It also derives the two ETS table names: `:"<name>_data"` and `:"<name>_order"`. Both are named tables, so those exact atoms are the tables' names and callers may inspect them (e.g. `:ets.info(:"<name>_data", :size)` is the current entry count).
- `:max_size` is required and must be a positive integer (`> 0`). If it is missing, or if it is present but is not an integer or is not greater than zero (e.g. `0`, `-1`, `1.5`, `:many`), starting the cache must fail with an `ArgumentError` raised during initialisation. A missing `:name` likewise fails with the error `Keyword.fetch!/2` raises.
- The data table must be readable from any process (so `get/2` can read it without going through the server); the order table need not be.
- A freshly started cache is empty: any `get/2` on it returns `:miss`.

### `get/2`

- On a hit, returns `{:ok, value}` and, as a side effect, increments that entry's frequency by 1 and refreshes its recency to "most recently used". The frequency bump is committed before `get/2` returns, so a subsequent `put/3` that triggers eviction already sees the new frequency.
- On a miss, returns `:miss` and changes nothing: no entry is created, no frequency changes, no recency changes, and no eviction happens. Repeated misses on the same unknown key stay `:miss` forever until a `put/3` creates it.
- `get/2` never evicts anything and never changes the number of entries.
- Any term may be used as a key (atoms, tuples, integers, …) and any term as a value; keys are compared as ETS `:set` keys.

### `put/3`

- Always returns `:ok` — there is no error return, and no way for a caller to observe *which* entry (if any) was evicted from the return value.
- **New key, cache below `max_size`:** the entry is inserted with frequency `1` and becomes the most recently used entry. Nothing is evicted.
- **Existing key:** the value is overwritten, the frequency is incremented by 1, and the entry becomes the most recently used. The entry count does not change, and **no eviction occurs even when the cache is exactly at `max_size`** — updating a key that is already present must never evict anything, not even itself.
- **New key, cache exactly at `max_size`:** exactly one entry is evicted *before* the new one is inserted, so the entry count after the call is still `max_size`. The victim is the entry with the lowest frequency; among entries tied at that lowest frequency, the victim is the one accessed longest ago. The evicted key is fully gone: a later `get/2` for it returns `:miss`, and re-`put`ting it starts it over at frequency `1` (its old frequency is not remembered).
- With `max_size: 1`, putting a second, different key evicts the first one, leaving exactly one entry.

### Recency and ordering

- "Recency" is a single monotonically increasing counter (`seq`) held in the GenServer state — never a wall-clock value — so ordering is deterministic and reproducible without any clock mocking.
- Every access draws a fresh, strictly larger `seq`: a hit in `get/2`, a `put/3` that inserts, and a `put/3` that updates. A `get/2` miss draws nothing and must not perturb the ordering of other entries.
- Ordering is therefore total: no two live entries ever share a recency stamp, so the eviction victim is always unique and eviction is fully deterministic given the sequence of calls.
- Consequence worth stating explicitly: touching an entry (via `get/2` or an update `put/3`) both raises its frequency *and* makes it the newest, so it moves to the back of the eviction queue on both axes.

## Implementation requirements

- Use two ETS tables owned by the GenServer: one that maps `key → {value, frequency, seq}` for O(1) lookups — each row stored literally as the two-element tuple `{key, {value, frequency, seq}}` (the triple nested, not flattened into the row), since callers may read rows directly — and one ordered set whose key is the composite `{frequency, seq}` (mapping to the cache key) so the least-frequently-used entry — with a least-recently-used tie-break — is always at the front for O(log n) eviction.
- The two tables must stay consistent: for every key in the data table there is exactly one entry in the order table, keyed by that key's current `{frequency, seq}` — stale composite keys must be removed when an entry is touched, updated, or evicted.
- All mutations (`put`, eviction, and the frequency bump on `get`) must go through the GenServer process to serialise writes; reads may read directly from ETS first. Because mutations are serialised through synchronous calls, concurrent callers observe a single well-defined interleaving.
- A frequency bump requested for a key that has since vanished (e.g. it was evicted between the direct ETS read and the server call) must be a harmless no-op rather than a crash or a resurrected entry.
- There is no TTL, no background cleanup, and no maximum frequency: entries only leave the cache through frequency-based eviction, and frequencies grow without bound.
- Provide a `child_spec/1` so the cache can be placed directly in a supervision tree with the same `opts` keyword list.

Give me the complete module in a single file. Use only the OTP standard library — no external dependencies.
