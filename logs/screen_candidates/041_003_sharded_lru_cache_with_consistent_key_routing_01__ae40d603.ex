defmodule LRUCacheSharded do
  @moduledoc """
  A sharded LRU cache backed by ETS.

  Instead of funnelling every mutation through a single `GenServer`, keys are spread
  across `num_shards` independent shard processes. A key is always routed to the same
  shard via `:erlang.phash2(key, num_shards)`, and each shard is a self-contained LRU
  cache — its own pair of ETS tables, its own monotonic recency counter, and its own
  capacity of `max_size` entries.

  Consequences of that design:

    * Two keys on different shards never serialise against each other.
    * Eviction is strictly per-shard: overflowing shard `i` never removes an entry from
      shard `j`. The cache as a whole holds up to `num_shards * max_size` entries, but a
      single shard is capped at `max_size` no matter how empty the others are.

  Routing is published in a public named ETS table owned by the façade process, so
  `get/2`, `put/3`, `num_shards/1`, `shard_index/2` and `size/1` read it directly and
  never call into the owner process.

  ## Example

      {:ok, _pid} = LRUCacheSharded.start_link(name: :my_cache, num_shards: 4, max_size: 2)
      :ok = LRUCacheSharded.put(:my_cache, :a, 1)
      {:ok, 1} = LRUCacheSharded.get(:my_cache, :a)
      :miss = LRUCacheSharded.get(:my_cache, :nope)

  All three options (`:name`, `:num_shards`, `:max_size`) are required. `:name` is
  fetched in `start_link/1`, so a missing `:name` raises `KeyError` in the caller;
  `:num_shards` and `:max_size` are fetched and validated in `init/1`, so problems there
  surface as `{:error, {exception, stacktrace}}` from `start_link/1`.
  """

  use GenServer

  @typedoc "The registered name of a cache."
  @type name :: atom()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Returns a child specification so the cache can be placed directly under a supervisor.

  The child `id` is the `:name` option, the type is `:worker`, the restart is
  `:permanent` and the shutdown timeout is 5000 ms. The original `opts` are passed
  through unchanged to `start_link/1`.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.fetch!(opts, :name),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @doc """
  Starts the cache owner process and its shards.

  Required options:

    * `:name` — atom the owner registers under; all shard and table names are derived
      from it. Fetched here, so a missing `:name` raises `KeyError` in the caller.
    * `:num_shards` — positive integer, the number of shard processes.
    * `:max_size` — positive integer, the capacity of *each* shard.

  `:num_shards` and `:max_size` are fetched and validated during `init/1`; a missing or
  invalid value therefore returns `{:error, {exception, stacktrace}}` rather than raising
  in the caller.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, {name, opts}, name: name)
  end

  @doc """
  Returns the configured shard count for `name`.

  Read straight from the routing ETS table; never calls the owner process.
  """
  @spec num_shards(name()) :: pos_integer()
  def num_shards(name) do
    [{:num_shards, count}] = :ets.lookup(routing_table(name), :num_shards)
    count
  end

  @doc """
  Returns the shard index `key` routes to, i.e. `:erlang.phash2(key, num_shards(name))`.

  Total (defined for any term), deterministic, and always in `0..num_shards - 1`.
  """
  @spec shard_index(name(), term()) :: non_neg_integer()
  def shard_index(name, key), do: :erlang.phash2(key, num_shards(name))

  @doc """
  Fetches `key`, returning `{:ok, value}` on a hit or `:miss` otherwise.

  A hit counts as a use: it makes `key` the most-recently-used entry within its own
  shard. The value is read directly from the shard's ETS table, but the recency refresh
  is serialised through the shard process, so the refresh is already visible to a
  subsequent `put/3` on that shard by the time this call returns.
  """
  @spec get(name(), term()) :: {:ok, term()} | :miss
  def get(name, key) do
    index = shard_index(name, key)

    case :ets.lookup(data_table(name, index), key) do
      [{^key, value, _timestamp}] ->
        case GenServer.call(shard_name(name, index), {:touch, key}) do
          :ok -> {:ok, value}
          :miss -> :miss
        end

      [] ->
        :miss
    end
  end

  @doc """
  Stores `value` under `key`, always returning `:ok`.

  Inserting a new key into a shard already holding `max_size` entries evicts exactly one
  entry — that shard's least-recently-used one — before inserting. Updating an existing
  key replaces the value in place and refreshes its recency without changing the shard's
  entry count and without evicting anything.
  """
  @spec put(name(), term(), term()) :: :ok
  def put(name, key, value) do
    index = shard_index(name, key)
    GenServer.call(shard_name(name, index), {:put, key, value})
  end

  @doc """
  Returns the total number of entries across all shards.

  Never exceeds `num_shards * max_size`, and is `0` for a freshly started cache.
  """
  @spec size(name()) :: non_neg_integer()
  def size(name) do
    count = num_shards(name)

    Enum.reduce(0..(count - 1), 0, fn index, acc ->
      acc + :ets.info(data_table(name, index), :size)
    end)
  end

  # ---------------------------------------------------------------------------
  # Name derivation (shared with the shard module)
  # ---------------------------------------------------------------------------

  @doc false
  @spec routing_table(name()) :: atom()
  def routing_table(name), do: :"#{name}_routing"

  @doc false
  @spec shard_name(name(), non_neg_integer()) :: atom()
  def shard_name(name, index), do: :"#{name}_shard_#{index}"

  @doc false
  @spec data_table(name(), non_neg_integer()) :: atom()
  def data_table(name, index), do: :"#{name}_data_#{index}"

  @doc false
  @spec order_table(name(), non_neg_integer()) :: atom()
  def order_table(name, index), do: :"#{name}_order_#{index}"

  # ---------------------------------------------------------------------------
  # Owner callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init({name, opts}) do
    num_shards = Keyword.fetch!(opts, :num_shards)
    max_size = Keyword.fetch!(opts, :max_size)

    validate_positive_integer!(:num_shards, num_shards)
    validate_positive_integer!(:max_size, max_size)

    :ets.new(routing_table(name), [:set, :public, :named_table, read_concurrency: true])
    :ets.insert(routing_table(name), {:num_shards, num_shards})

    for index <- 0..(num_shards - 1) do
      {:ok, _pid} =
        LRUCacheSharded.Shard.start_link(
          parent: name,
          index: index,
          max_size: max_size
        )
    end

    {:ok, %{name: name, num_shards: num_shards, max_size: max_size}}
  end

  defp validate_positive_integer!(option, value) when is_integer(value) and value > 0 do
    {option, value}
  end

  defp validate_positive_integer!(option, value) do
    raise ArgumentError,
          "expected #{inspect(option)} to be a positive integer, got: #{inspect(value)}"
  end
end

defmodule LRUCacheSharded.Shard do
  @moduledoc """
  A single shard of `LRUCacheSharded`: an independent LRU cache of capacity `max_size`.

  Each shard owns two named ETS tables — a `:set` data table mapping
  `key -> {value, timestamp}` and an `:ordered_set` order table mapping
  `timestamp -> key` — plus a monotonically increasing integer counter held in the
  process state and used as the timestamp. The counter starts at `0` and increments by
  one on every recency-affecting operation, so ordering is total, deterministic and
  testable without any wall-clock reads.

  Reads may hit the data table directly; every write (put, eviction, touch-on-get) is
  serialised through this process.
  """

  use GenServer

  alias LRUCacheSharded, as: Cache

  @doc """
  Starts a shard process, linked to the caller.

  Required options: `:parent` (the façade's registered name), `:index` (the shard index)
  and `:max_size` (this shard's capacity).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    parent = Keyword.fetch!(opts, :parent)
    index = Keyword.fetch!(opts, :index)
    max_size = Keyword.fetch!(opts, :max_size)

    GenServer.start_link(__MODULE__, {parent, index, max_size},
      name: Cache.shard_name(parent, index)
    )
  end

  @impl GenServer
  def init({parent, index, max_size}) do
    data = Cache.data_table(parent, index)
    order = Cache.order_table(parent, index)

    :ets.new(data, [:set, :public, :named_table, read_concurrency: true])
    :ets.new(order, [:ordered_set, :public, :named_table])

    {:ok, %{data: data, order: order, max_size: max_size, counter: 0}}
  end

  @impl GenServer
  def handle_call({:put, key, value}, _from, state) do
    {timestamp, state} = next_timestamp(state)

    case :ets.lookup(state.data, key) do
      [{^key, _old_value, old_timestamp}] ->
        :ets.delete(state.order, old_timestamp)

      [] ->
        maybe_evict(state)
    end

    :ets.insert(state.data, {key, value, timestamp})
    :ets.insert(state.order, {timestamp, key})

    {:reply, :ok, state}
  end

  def handle_call({:touch, key}, _from, state) do
    case :ets.lookup(state.data, key) do
      [{^key, value, old_timestamp}] ->
        {timestamp, state} = next_timestamp(state)
        :ets.delete(state.order, old_timestamp)
        :ets.insert(state.data, {key, value, timestamp})
        :ets.insert(state.order, {timestamp, key})
        {:reply, :ok, state}

      [] ->
        {:reply, :miss, state}
    end
  end

  defp next_timestamp(%{counter: counter} = state) do
    {counter, %{state | counter: counter + 1}}
  end

  defp maybe_evict(state) do
    if :ets.info(state.data, :size) >= state.max_size do
      case :ets.first(state.order) do
        :"$end_of_table" ->
          :ok

        oldest ->
          [{^oldest, victim}] = :ets.lookup(state.order, oldest)
          :ets.delete(state.order, oldest)
          :ets.delete(state.data, victim)
          :ok
      end
    else
      :ok
    end
  end
end