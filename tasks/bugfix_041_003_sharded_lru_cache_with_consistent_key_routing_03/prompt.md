# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir module called `LRUCacheSharded` that implements a **sharded** LRU cache backed by ETS, designed to reduce write contention by spreading keys across several independent shard processes instead of funnelling every mutation through a single GenServer.

The public façade is `LRUCacheSharded`, and internally it owns N shard GenServers, each of which is a self-contained LRU cache (with its own pair of ETS tables and its own monotonic recency counter). A key is always routed to the same shard via `:erlang.phash2(key, num_shards)`, and each shard enforces LRU eviction independently against a **per-shard** capacity.

I need this public API:
- `LRUCacheSharded.start_link(opts)` — accepts `:name` (required, registers the owner process and derives all table/shard names), `:num_shards` (required, a positive integer — how many shard processes to spawn), and `:max_size` (required, a positive integer — the per-shard capacity).
- `LRUCacheSharded.get(name, key)` — returns `{:ok, value}` or `:miss`. A hit refreshes recency within that key's shard. Routing must not go through the owner process (read the routing info from ETS directly and call the correct shard), so different keys on different shards never serialise against each other.
- `LRUCacheSharded.put(name, key, value)` — inserts/updates within the key's shard; on a full shard it evicts that shard's least-recently-used entry. Always returns `:ok`.
- `LRUCacheSharded.num_shards(name)` — returns the configured shard count.
- `LRUCacheSharded.shard_index(name, key)` — returns the integer shard index a key routes to (so callers/tests can reason about co-location).
- `LRUCacheSharded.size(name)` — returns the total number of entries across all shards.

Implementation requirements:
- The owner process, in `init/1`, must create a public named routing ETS table recording the shard count, then start one linked shard GenServer per shard. Each shard owns a `:set` data table (`key → {value, timestamp}`) and an `:ordered_set` order table (`timestamp → key`), using a monotonically increasing integer counter in its state as the timestamp — deterministic and testable without clock mocking.
- `get`/`put`/`shard_index`/`num_shards`/`size` must compute routing by reading the routing ETS table (never a call into the owner), so the owner is not a hot path.
- Each shard serialises its own writes (put, eviction, touch-on-get) through its own GenServer; reads may hit that shard's ETS table directly.
- Eviction is strictly per-shard: filling one shard beyond capacity must never evict entries that live in another shard.

Give me the complete module (owner plus the internal shard module) in a single file. Use only the OTP standard library — no external dependencies.

## The buggy module

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

    {:error, %{name: name, routing: routing, shards: shards}}
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

## Failing test report

```
10 of 10 test(s) failed:

  * test num_shards: 1 behaves like a plain LRU cache
      failed to start child with the spec {LRUCacheSharded, [name: :shard_4807, num_shards: 1, max_size: 3]}.
      Reason: %{name: :shard_4807, routing: :shard_4807_routing, shards: [shard_4807_shard_0: #PID<0.213.0>]}

  * test get refreshes recency within a single shard
      failed to start child with the spec {LRUCacheSharded, [name: :shard_4871, num_shards: 1, max_size: 3]}.
      Reason: %{name: :shard_4871, routing: :shard_4871_routing, shards: [shard_4871_shard_0: #PID<0.217.0>]}

  * test get returns :miss for unknown key
      failed to start child with the spec {LRUCacheSharded, [name: :shard_4935, num_shards: 4, max_size: 10]}.
      Reason: %{name: :shard_4935, routing: :shard_4935_routing, shards: [shard_4935_shard_0: #PID<0.221.0>, shard_4935_shard_1: #PID<0.222.0>, shard_4935_shard_2: #PID<0.223.0>, shard_4935_shard_3: #PID<0.224.0>]}

  * test put and get round-trip across shards
      failed to start child with the spec {LRUCacheSharded, [name: :shard_4999, num_shards: 4, max_size: 10]}.
      Reason: %{name: :shard_4999, routing: :shard_4999_routing, shards: [shard_4999_shard_0: #PID<0.228.0>, shard_4999_shard_1: #PID<0.229.0>, shard_4999_shard_2: #PID<0.230.0>, shard_4999_shard_3: #PID<0.231.0>]}

  (…6 more)
```
