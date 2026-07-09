# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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
  @spec put(name(), key(), value()) :: :ok
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

## Test harness — implement the `# TODO` test

```elixir
defmodule LRUCacheShardedTest do
  use ExUnit.Case, async: false

  defp start_cache(num_shards, max_size) do
    name = :"shard_#{System.unique_integer([:positive])}"
    start_supervised!({LRUCacheSharded, name: name, num_shards: num_shards, max_size: max_size})
    name
  end

  # Find `count` integer keys that all route to the same shard.
  defp colliding_keys(name, count) do
    1..5000
    |> Enum.group_by(fn k -> LRUCacheSharded.shard_index(name, k) end)
    |> Enum.find_value(fn {_idx, keys} ->
      if length(keys) >= count, do: Enum.take(keys, count), else: nil
    end)
  end

  # -------------------------------------------------------
  # Single-shard behaves as a plain LRU cache
  # -------------------------------------------------------

  test "num_shards: 1 behaves like a plain LRU cache" do
    c = start_cache(1, 3)
    LRUCacheSharded.put(c, :a, 1)
    LRUCacheSharded.put(c, :b, 2)
    LRUCacheSharded.put(c, :c, 3)
    # evicts :a (LRU)
    LRUCacheSharded.put(c, :d, 4)

    assert :miss = LRUCacheSharded.get(c, :a)
    assert {:ok, 2} = LRUCacheSharded.get(c, :b)
    assert {:ok, 3} = LRUCacheSharded.get(c, :c)
    assert {:ok, 4} = LRUCacheSharded.get(c, :d)
  end

  test "get refreshes recency within a single shard" do
    c = start_cache(1, 3)
    LRUCacheSharded.put(c, :a, 1)
    LRUCacheSharded.put(c, :b, 2)
    LRUCacheSharded.put(c, :c, 3)
    # touch :a → :b becomes LRU
    LRUCacheSharded.get(c, :a)
    LRUCacheSharded.put(c, :d, 4)

    assert {:ok, 1} = LRUCacheSharded.get(c, :a)
    assert :miss = LRUCacheSharded.get(c, :b)
  end

  # -------------------------------------------------------
  # Basic API
  # -------------------------------------------------------

  test "get returns :miss for unknown key" do
    c = start_cache(4, 10)
    assert :miss = LRUCacheSharded.get(c, :nope)
  end

  test "put and get round-trip across shards" do
    c = start_cache(4, 10)
    for i <- 1..20, do: LRUCacheSharded.put(c, i, i * 100)

    for i <- 1..20 do
      expected = i * 100
      assert {:ok, ^expected} = LRUCacheSharded.get(c, i)
    end
  end

  test "num_shards reports the configured shard count" do
    # TODO
  end

  test "shard_index is deterministic and in range" do
    c = start_cache(4, 5)

    for k <- 1..50 do
      idx = LRUCacheSharded.shard_index(c, k)
      assert idx >= 0 and idx < 4
      assert LRUCacheSharded.shard_index(c, k) == idx
    end
  end

  # -------------------------------------------------------
  # Per-shard eviction
  # -------------------------------------------------------

  test "eviction is confined to the key's own shard" do
    c = start_cache(4, 2)
    [k1, k2, k3] = colliding_keys(c, 3)

    LRUCacheSharded.put(c, k1, :v1)
    LRUCacheSharded.put(c, k2, :v2)
    # shard capacity is 2 → inserting k3 evicts k1 (LRU) within that shard
    LRUCacheSharded.put(c, k3, :v3)

    assert :miss = LRUCacheSharded.get(c, k1)
    assert {:ok, :v2} = LRUCacheSharded.get(c, k2)
    assert {:ok, :v3} = LRUCacheSharded.get(c, k3)
  end

  test "filling one shard does not evict entries in another shard" do
    c = start_cache(4, 2)

    grouped =
      1..5000
      |> Enum.group_by(fn k -> LRUCacheSharded.shard_index(c, k) end)

    # pick two distinct shards that each have at least 3 keys
    [{_ia, a_keys}, {_ib, b_keys} | _] =
      grouped
      |> Enum.filter(fn {_i, ks} -> length(ks) >= 3 end)
      |> Enum.take(2)

    [a1, a2, a3] = Enum.take(a_keys, 3)
    [b1 | _] = b_keys

    # park a survivor in shard B
    LRUCacheSharded.put(c, b1, :survivor)

    # overflow shard A
    LRUCacheSharded.put(c, a1, 1)
    LRUCacheSharded.put(c, a2, 2)
    LRUCacheSharded.put(c, a3, 3)

    # a1 evicted from shard A, but shard B's entry is untouched
    assert :miss = LRUCacheSharded.get(c, a1)
    assert {:ok, :survivor} = LRUCacheSharded.get(c, b1)
  end

  # -------------------------------------------------------
  # size/1
  # -------------------------------------------------------

  test "size reports total entries across shards and respects per-shard caps" do
    c = start_cache(4, 2)
    # 4 shards * cap 2 = at most 8 entries retained
    for i <- 1..100, do: LRUCacheSharded.put(c, i, i)
    total = LRUCacheSharded.size(c)
    assert total <= 8
    assert total > 0
  end

  # -------------------------------------------------------
  # Independence between instances
  # -------------------------------------------------------

  test "two sharded caches are fully independent" do
    c1 = start_cache(2, 4)
    c2 = start_cache(2, 4)

    LRUCacheSharded.put(c1, :k, :from_c1)
    LRUCacheSharded.put(c2, :k, :from_c2)

    assert {:ok, :from_c1} = LRUCacheSharded.get(c1, :k)
    assert {:ok, :from_c2} = LRUCacheSharded.get(c2, :k)
  end
end
```
