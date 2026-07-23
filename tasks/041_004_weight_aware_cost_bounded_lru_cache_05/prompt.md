# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `child_spec` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

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

## The module with `child_spec` missing

```elixir
defmodule WeightedLRUCache do
  @moduledoc """
  A cost/weight-bounded LRU cache backed by two ETS tables.

  The cache caps the *total weight* of resident entries (not their count).
  Every entry carries an explicit positive-integer weight, and the running
  total is kept exactly in sync in the GenServer state.

  ## ETS tables

  | Table          | Type           | Key → Value                       | Purpose               |
  |----------------|----------------|-----------------------------------|-----------------------|
  | `<name>_data`  | `:set`         | `key → {value, weight, timestamp}`| O(1) key lookup       |
  | `<name>_order` | `:ordered_set` | `timestamp → key`                 | O(log n) LRU eviction |

  `timestamp` is a monotonically increasing integer counter kept in state —
  never wall-clock — so recency ordering is deterministic and testable.

  ## Failure semantics of `put/4`

  * `{:error, :invalid_weight}` – weight is not a positive integer; nothing changes.
  * `{:error, :too_large}` – weight alone exceeds `max_weight`; nothing changes
    and nothing is evicted.
  * `:ok` – LRU entries are evicted one at a time until the newcomer fits, then
    it is inserted as most-recently-used. Updating an existing key releases its
    old weight first, then re-inserts it (possibly evicting *other* entries).
  """

  use GenServer

  def child_spec(opts) do
    # TODO
  end

  @type name :: atom()
  @type key :: term()
  @type value :: term()

  @doc """
  Start and link a `WeightedLRUCache`.

  ## Options

  * `:name` (required) – atom to register the process and derive ETS table names.
  * `:max_weight` (required) – positive integer total weight budget.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Look up `key`, refreshing recency. `{:ok, value}` or `:miss`."
  @spec get(name(), key()) :: {:ok, value()} | :miss
  def get(name, key) do
    case :ets.lookup(data_table_name(name), key) do
      [{^key, {value, _weight, _ts}}] ->
        GenServer.call(name, {:touch, key})
        {:ok, value}

      [] ->
        :miss
    end
  end

  @doc """
  Insert or update `key` with `value` and `weight`. See the moduledoc for the
  `{:error, :invalid_weight}` / `{:error, :too_large}` / `:ok` semantics.
  """
  @spec put(name(), key(), value(), integer()) ::
          :ok | {:error, :invalid_weight | :too_large}
  def put(name, key, value, weight) do
    GenServer.call(name, {:put, key, value, weight})
  end

  @doc "Current total resident weight."
  @spec weight(name()) :: non_neg_integer()
  def weight(name), do: GenServer.call(name, :weight)

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    max_weight = Keyword.fetch!(opts, :max_weight)

    unless is_integer(max_weight) and max_weight > 0 do
      raise ArgumentError, ":max_weight must be a positive integer, got: #{inspect(max_weight)}"
    end

    data_table =
      :ets.new(data_table_name(name), [
        :set,
        :public,
        :named_table,
        read_concurrency: true
      ])

    order_table =
      :ets.new(order_table_name(name), [
        :ordered_set,
        :protected,
        :named_table
      ])

    state = %{
      data_table: data_table,
      order_table: order_table,
      max_weight: max_weight,
      total_weight: 0,
      counter: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:weight, _from, state) do
    {:reply, state.total_weight, state}
  end

  def handle_call({:touch, key}, _from, state) do
    case :ets.lookup(state.data_table, key) do
      [{^key, {value, w, old_ts}}] ->
        {new_ts, state} = next_counter(state)
        :ets.delete(state.order_table, old_ts)
        :ets.insert(state.order_table, {new_ts, key})
        :ets.insert(state.data_table, {key, {value, w, new_ts}})
        {:reply, :ok, state}

      [] ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:put, key, value, weight}, _from, state) do
    cond do
      not (is_integer(weight) and weight > 0) ->
        {:reply, {:error, :invalid_weight}, state}

      weight > state.max_weight ->
        {:reply, {:error, :too_large}, state}

      true ->
        # Treat an update as remove-then-insert: release the old weight first.
        state = release_existing(state, key)
        state = evict_until_fits(state, weight)

        {new_ts, state} = next_counter(state)
        :ets.insert(state.order_table, {new_ts, key})
        :ets.insert(state.data_table, {key, {value, weight, new_ts}})
        state = %{state | total_weight: state.total_weight + weight}

        {:reply, :ok, state}
    end
  end

  defp next_counter(%{counter: c} = state), do: {c + 1, %{state | counter: c + 1}}

  # Remove an existing entry for `key` (if any) and reclaim its weight.
  defp release_existing(state, key) do
    case :ets.lookup(state.data_table, key) do
      [{^key, {_old_value, old_w, old_ts}}] ->
        :ets.delete(state.order_table, old_ts)
        :ets.delete(state.data_table, key)
        %{state | total_weight: state.total_weight - old_w}

      [] ->
        state
    end
  end

  # Evict LRU entries one at a time until `incoming` fits within the budget.
  defp evict_until_fits(state, incoming) do
    if state.total_weight + incoming > state.max_weight and
         :ets.info(state.data_table, :size) > 0 do
      lru_ts = :ets.first(state.order_table)
      [{^lru_ts, victim}] = :ets.lookup(state.order_table, lru_ts)
      [{^victim, {_v, victim_w, ^lru_ts}}] = :ets.lookup(state.data_table, victim)
      :ets.delete(state.order_table, lru_ts)
      :ets.delete(state.data_table, victim)
      evict_until_fits(%{state | total_weight: state.total_weight - victim_w}, incoming)
    else
      state
    end
  end

  defp data_table_name(name), do: :"#{name}_data"
  defp order_table_name(name), do: :"#{name}_order"
end
```

Reply with `child_spec` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
