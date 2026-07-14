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

  The *timestamp* is a monotonically increasing integer counter kept in the
  GenServer state – never a wall-clock value – so the cache is fully
  deterministic and testable without any clock mocking.

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

Write me an Elixir GenServer module called `WeightedLRUCache` that implements a **cost/weight-bounded** LRU cache backed by ETS.

Unlike a plain LRU cache that caps the *number* of entries, this cache caps the *total weight* of all entries. Every entry carries an explicit integer weight (think bytes, or cost units), and the cache guarantees the sum of the weights of all resident entries never exceeds `max_weight`.

I need this public API:
- `WeightedLRUCache.start_link(opts)` — accepts `:name` (required, registers the process and names the ETS tables) and `:max_weight` (required, a positive integer — the total weight budget).
- `WeightedLRUCache.get(name, key)` — returns `{:ok, value}` or `:miss`. A hit refreshes the entry's recency.
- `WeightedLRUCache.put(name, key, value, weight)` — inserts or updates an entry with the given weight. Return values encode the failure semantics:
  - If `weight` is not a positive integer, return `{:error, :invalid_weight}` and change nothing.
  - If `weight` alone exceeds `max_weight`, the entry can never fit: return `{:error, :too_large}`, change nothing, and do **not** evict anything.
  - Otherwise return `:ok`. Before inserting, evict least-recently-used entries one at a time until the new entry fits within the budget. Updating an existing key is treated as replacing it: its old weight is released first, then it is re-inserted as the most-recently-used entry (which may itself trigger eviction of *other* entries).
- `WeightedLRUCache.weight(name)` — returns the current total resident weight.

Implementation requirements:
- Use two ETS tables owned by the GenServer: a `:set` mapping `key → {value, weight, timestamp}` for O(1) lookups, and an `:ordered_set` mapping `timestamp → key` to find the LRU entry for eviction.
- Use a monotonically increasing integer counter in the GenServer state as the timestamp, so recency ordering is deterministic and testable without clock mocking.
- Track the running total weight in the GenServer state and keep it exactly in sync as entries are inserted, updated, and evicted.
- All mutations (put, eviction, touch-on-get) go through the GenServer to serialise writes; reads may hit ETS directly.
- Eviction removes whole entries (never partial). A single `put` may evict several entries in a row to make room. There is no TTL or background cleanup.

Give me the complete module in a single file. Use only the OTP standard library — no external dependencies.
