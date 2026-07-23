# Fill in one @spec

Below: a working module where the `@spec` for
`put/3` has been removed (see the `# TODO: @spec` marker).
Provide exactly that typespec, consistent with the implementation's
arguments, guards, and all reachable return shapes. No other edits.

## The module with the `@spec` for `put/3` missing

```elixir
defmodule LRUCacheSharded do
  @moduledoc """
  A sharded LRU cache backed by ETS.

  Instead of serialising every write through one GenServer, keys are spread
  across `num_shards` independent shard processes. A key is routed to a shard
  by `:erlang.phash2(key, num_shards)`, so writes to keys on different shards
  never contend on the same process.

  ## Topology

  * An **owner** process (registered under `:name`) creates a public,
    named routing ETS table and starts one linked shard GenServer per shard.
  * Each **shard** (`LRUCacheSharded.Shard`) is a self-contained LRU cache with
    its own `:set` data table, `:ordered_set` order table, and monotonic
    recency counter, enforcing LRU eviction against a per-shard `max_size`.

  Routing (`get`, `put`, `size`, `shard_index`, `num_shards`) reads the routing
  ETS table directly — the owner is never on the hot path.

  Eviction is strictly per-shard: overflowing one shard never touches another.
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
  Start and link the owner process.

  ## Options

  * `:name` (required) – atom used to register the owner and derive shard names.
  * `:num_shards` (required) – positive integer number of shard processes.
  * `:max_size` (required) – positive integer per-shard capacity.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Look up `key`, refreshing recency in its shard. `{:ok, value}` or `:miss`."
  @spec get(name(), key()) :: {:ok, value()} | :miss
  def get(name, key) do
    key
    |> shard_name(name)
    |> LRUCacheSharded.Shard.get(key)
  end

  @doc "Insert/update `key` in its shard. Always returns `:ok`."
  # TODO: @spec
  def put(name, key, value) do
    key
    |> shard_name(name)
    |> LRUCacheSharded.Shard.put(key, value)
  end

  @doc "The configured number of shards."
  @spec num_shards(name()) :: pos_integer()
  def num_shards(name) do
    [{:__num_shards__, n}] = :ets.lookup(routing_table_name(name), :__num_shards__)
    n
  end

  @doc "The shard index a key routes to."
  @spec shard_index(name(), key()) :: non_neg_integer()
  def shard_index(name, key), do: :erlang.phash2(key, num_shards(name))

  @doc "Total number of entries across all shards."
  @spec size(name()) :: non_neg_integer()
  def size(name) do
    n = num_shards(name)

    Enum.reduce(0..(n - 1), 0, fn i, acc ->
      acc + LRUCacheSharded.Shard.size(shard_name_for_index(name, i))
    end)
  end

  # ---- routing helpers ----

  defp shard_name(key, name) do
    n = num_shards(name)
    shard_name_for_index(name, :erlang.phash2(key, n))
  end

  defp shard_name_for_index(name, idx), do: :"#{name}_shard_#{idx}"
  defp routing_table_name(name), do: :"#{name}_routing"

  # ---- owner callbacks ----

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    num_shards = Keyword.fetch!(opts, :num_shards)
    max_size = Keyword.fetch!(opts, :max_size)

    unless is_integer(num_shards) and num_shards > 0 do
      raise ArgumentError, ":num_shards must be a positive integer, got: #{inspect(num_shards)}"
    end

    unless is_integer(max_size) and max_size > 0 do
      raise ArgumentError, ":max_size must be a positive integer, got: #{inspect(max_size)}"
    end

    routing =
      :ets.new(routing_table_name(name), [
        :set,
        :public,
        :named_table,
        read_concurrency: true
      ])

    :ets.insert(routing, {:__num_shards__, num_shards})

    shards =
      for i <- 0..(num_shards - 1) do
        shard = shard_name_for_index(name, i)
        {:ok, pid} = LRUCacheSharded.Shard.start_link(name: shard, max_size: max_size)
        {shard, pid}
      end

    {:ok, %{name: name, routing: routing, shards: shards}}
  end
end

defmodule LRUCacheSharded.Shard do
  @moduledoc """
  A single LRU shard: one `:set` data table (`key → {value, timestamp}`) and one
  `:ordered_set` order table (`timestamp → key`), with a monotonic integer
  counter as the deterministic timestamp. Writes are serialised through this
  GenServer; reads hit the data table directly.
  """

  use GenServer

  @doc false
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc false
  def get(name, key) do
    case :ets.lookup(data_table_name(name), key) do
      [{^key, {value, _ts}}] ->
        GenServer.call(name, {:touch, key})
        {:ok, value}

      [] ->
        :miss
    end
  end

  @doc false
  def put(name, key, value), do: GenServer.call(name, {:put, key, value})

  @doc false
  def size(name), do: :ets.info(data_table_name(name), :size)

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    max_size = Keyword.fetch!(opts, :max_size)

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

    {:ok, %{data_table: data_table, order_table: order_table, max_size: max_size, counter: 0}}
  end

  @impl true
  def handle_call({:touch, key}, _from, state) do
    case :ets.lookup(state.data_table, key) do
      [{^key, {value, old_ts}}] ->
        {new_ts, state} = next_counter(state)
        :ets.delete(state.order_table, old_ts)
        :ets.insert(state.order_table, {new_ts, key})
        :ets.insert(state.data_table, {key, {value, new_ts}})
        {:reply, :ok, state}

      [] ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:put, key, value}, _from, state) do
    state =
      case :ets.lookup(state.data_table, key) do
        [{^key, {_old, old_ts}}] ->
          {new_ts, state} = next_counter(state)
          :ets.delete(state.order_table, old_ts)
          :ets.insert(state.order_table, {new_ts, key})
          :ets.insert(state.data_table, {key, {value, new_ts}})
          state

        [] ->
          state = maybe_evict(state)
          {new_ts, state} = next_counter(state)
          :ets.insert(state.order_table, {new_ts, key})
          :ets.insert(state.data_table, {key, {value, new_ts}})
          state
      end

    {:reply, :ok, state}
  end

  defp next_counter(%{counter: c} = state), do: {c + 1, %{state | counter: c + 1}}

  defp maybe_evict(state) do
    if :ets.info(state.data_table, :size) >= state.max_size do
      lru_ts = :ets.first(state.order_table)
      [{^lru_ts, lru_key}] = :ets.lookup(state.order_table, lru_ts)
      :ets.delete(state.order_table, lru_ts)
      :ets.delete(state.data_table, lru_key)
    end

    state
  end

  defp data_table_name(name), do: :"#{name}_data"
  defp order_table_name(name), do: :"#{name}_order"
end
```

The `@spec` attribute only — nothing more.
