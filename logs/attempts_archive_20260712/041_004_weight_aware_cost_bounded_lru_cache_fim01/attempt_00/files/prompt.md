Implement the private `evict_until_fits/2` function.

`evict_until_fits(state, incoming)` prepares room in the cache for a new entry
of weight `incoming` by evicting least-recently-used entries one at a time. It
returns the updated `state` (with `total_weight` and the ETS tables kept in
sync) once the newcomer will fit within `max_weight`.

Behaviour:

- It should keep evicting while **both** of these hold: adding `incoming` to the
  current `total_weight` would exceed `state.max_weight`, **and** the data table
  still holds at least one entry (`:ets.info(state.data_table, :size) > 0`).
- To evict, find the least-recently-used entry: `:ets.first(state.order_table)`
  gives the smallest (oldest) timestamp; look it up in the order table to get the
  victim key, then look the victim up in the data table to get its weight.
- Delete the victim from **both** the order table (by timestamp) and the data
  table (by key), subtract the victim's weight from `total_weight`, and recurse
  with the updated state and the same `incoming`.
- When the entry already fits, or there is nothing left to evict, return `state`
  unchanged.

Eviction removes whole entries only (never partial), and a single call may evict
several entries in a row to make room.

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
    # TODO
  end

  defp data_table_name(name), do: :"#{name}_data"
  defp order_table_name(name), do: :"#{name}_order"
end
```