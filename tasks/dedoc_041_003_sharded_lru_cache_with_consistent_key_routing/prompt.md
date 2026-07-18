# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule LRUCacheSharded do
  use GenServer

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

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def get(name, key) do
    key
    |> shard_name(name)
    |> LRUCacheSharded.Shard.get(key)
  end

  def put(name, key, value) do
    key
    |> shard_name(name)
    |> LRUCacheSharded.Shard.put(key, value)
  end

  def num_shards(name) do
    [{:__num_shards__, n}] = :ets.lookup(routing_table_name(name), :__num_shards__)
    n
  end

  def shard_index(name, key), do: :erlang.phash2(key, num_shards(name))

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
  use GenServer

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def get(name, key) do
    case :ets.lookup(data_table_name(name), key) do
      [{^key, {value, _ts}}] ->
        GenServer.call(name, {:touch, key})
        {:ok, value}

      [] ->
        :miss
    end
  end

  def put(name, key, value), do: GenServer.call(name, {:put, key, value})

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
