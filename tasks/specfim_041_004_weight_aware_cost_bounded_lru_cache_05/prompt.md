# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`weight/1` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `weight/1`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `weight/1` missing

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
  # TODO: @spec
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
