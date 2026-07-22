defmodule LRUCacheSharded do
  @moduledoc """
  A sharded LRU (least-recently-used) cache backed by ETS.

  Instead of funnelling every mutation through a single `GenServer`, keys are
  spread across `num_shards` independent shard processes. Each shard is a
  self-contained LRU cache owning its own pair of ETS tables (a `:set` data
  table mapping `key -> {value, timestamp}` and an `:ordered_set` order table
  mapping `timestamp -> key`) plus its own monotonically increasing recency
  counter. Eviction is enforced per shard against a per-shard capacity
  (`:max_size`), so overflowing one shard never removes an entry belonging to
  another.

  Routing is deterministic: a key always lands on shard
  `:erlang.phash2(key, num_shards)`. The shard count lives in a public, named
  routing ETS table created by the owner process, so `get/2`, `put/3`,
  `num_shards/1`, `shard_index/2` and `size/1` all resolve routing by reading
  ETS directly — the owner process is never on the hot path and never
  serialises calls between different shards.

  ## Example

      iex> {:ok, _pid} = LRUCacheSharded.start_link(name: :my_cache, num_shards: 4, max_size: 2)
      iex> LRUCacheSharded.put(:my_cache, :a, 1)
      :ok
      iex> LRUCacheSharded.get(:my_cache, :a)
      {:ok, 1}
      iex> LRUCacheSharded.get(:my_cache, :nope)
      :miss

  The cache as a whole can hold up to `num_shards * max_size` entries; any
  single shard is capped at `max_size` regardless of how empty the others are.
  """

  use GenServer

  @typedoc "The registered name of the cache owner process."
  @type name :: atom()

  # ---------------------------------------------------------------------------
  # Child spec
  # ---------------------------------------------------------------------------

  @doc """
  Builds a supervisor child specification for this cache.

  Uses the `:name` option as the child `id`, a `:worker` type, a `:permanent`
  restart strategy and a 5000 ms shutdown timeout. `opts` are passed verbatim
  to `start_link/1`, so `:name`, `:num_shards` and `:max_size` are required.
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

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the cache owner process and its shard processes.

  Required options:

    * `:name` — an atom used to register the owner and to derive every shard
      and ETS table name deterministically;
    * `:num_shards` — a positive integer, the number of shard processes;
    * `:max_size` — a positive integer, the capacity of *each* shard.

  All three options are required: a missing one raises `KeyError`. A
  `:num_shards` or `:max_size` that is not a positive integer raises
  `ArgumentError` from within `init/1`, so a linked caller sees the start fail
  rather than a half-built cache.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    num_shards = Keyword.fetch!(opts, :num_shards)
    max_size = Keyword.fetch!(opts, :max_size)

    GenServer.start_link(
      __MODULE__,
      %{name: name, num_shards: num_shards, max_size: max_size},
      name: name
    )
  end

  @doc """
  Fetches the value stored under `key`.

  Returns `{:ok, value}` on a hit and the bare atom `:miss` otherwise. A hit
  counts as a use: it refreshes the key's recency inside its own shard, making
  it that shard's most-recently-used entry (and hence the last candidate for
  eviction there). The refresh is serialised through the shard process, so by
  the time this function returns the new recency is already visible to a
  subsequent `put/3` on the same shard.

  Routing is resolved from the routing ETS table, never via a call into the
  owner process.
  """
  @spec get(name(), term()) :: {:ok, term()} | :miss
  def get(name, key) do
    shard = shard_index(name, key)

    case :ets.lookup(shard_data_table(name, shard), key) do
      [{^key, {value, _timestamp}}] ->
        GenServer.call(shard_name(name, shard), {:touch, key})
        {:ok, value}

      [] ->
        :miss
    end
  end

  @doc """
  Inserts or updates `key` with `value` in the key's shard.

  Always returns `:ok`. Inserting a new key into a shard that already holds
  `max_size` entries evicts exactly one entry — that shard's least-recently-used
  one — before inserting. Updating an existing key replaces the value in place
  and refreshes its recency without changing the shard's entry count and without
  evicting anything, even at capacity.
  """
  @spec put(name(), term(), term()) :: :ok
  def put(name, key, value) do
    shard = shard_index(name, key)
    GenServer.call(shard_name(name, shard), {:put, key, value})
  end

  @doc """
  Returns the configured number of shards.

  Read straight from the routing ETS table; the value never changes for the
  life of the cache.
  """
  @spec num_shards(name()) :: pos_integer()
  def num_shards(name) do
    [{:num_shards, count}] = :ets.lookup(routing_table(name), :num_shards)
    count
  end

  @doc """
  Returns the shard index that `key` routes to.

  This is exactly `:erlang.phash2(key, num_shards(name))`, so it is total
  (defined for any term), deterministic, and always within
  `0..num_shards - 1`.
  """
  @spec shard_index(name(), term()) :: non_neg_integer()
  def shard_index(name, key) do
    :erlang.phash2(key, num_shards(name))
  end

  @doc """
  Returns the total number of entries currently held across all shards.

  `0` on a freshly started cache. It never exceeds `num_shards * max_size`,
  reflects evictions, and is unchanged by overwrites of existing keys.
  """
  @spec size(name()) :: non_neg_integer()
  def size(name) do
    0..(num_shards(name) - 1)
    |> Enum.reduce(0, fn shard, acc ->
      acc + :ets.info(shard_data_table(name, shard), :size)
    end)
  end

  # ---------------------------------------------------------------------------
  # Name derivation (deterministic, from `:name` + shard index)
  # ---------------------------------------------------------------------------

  @doc """
  Returns the name of the public routing ETS table for the cache `name`.
  """
  @spec routing_table(name()) :: atom()
  def routing_table(name), do: :"#{name}_routing"

  @doc """
  Returns the registered name of shard `index` of the cache `name`.
  """
  @spec shard_name(name(), non_neg_integer()) :: atom()
  def shard_name(name, index), do: :"#{name}_shard_#{index}"

  @doc """
  Returns the name of the data ETS table (`key -> {value, timestamp}`) for
  shard `index` of the cache `name`.
  """
  @spec shard_data_table(name(), non_neg_integer()) :: atom()
  def shard_data_table(name, index), do: :"#{name}_shard_#{index}_data"

  @doc """
  Returns the name of the order ETS table (`timestamp -> key`) for shard
  `index` of the cache `name`.
  """
  @spec shard_order_table(name(), non_neg_integer()) :: atom()
  def shard_order_table(name, index), do: :"#{name}_shard_#{index}_order"

  # ---------------------------------------------------------------------------
  # Owner GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(%{name: name, num_shards: num_shards, max_size: max_size}) do
    validate_pos_integer!(:num_shards, num_shards)
    validate_pos_integer!(:max_size, max_size)

    routing = routing_table(name)

    :ets.new(routing, [:set, :named_table, :public, read_concurrency: true])
    :ets.insert(routing, {:num_shards, num_shards})

    shards =
      for index <- 0..(num_shards - 1) do
        {:ok, pid} =
          LRUCacheSharded.Shard.start_link(
            cache: name,
            index: index,
            max_size: max_size
          )

        {index, pid}
      end

    {:ok, %{name: name, num_shards: num_shards, max_size: max_size, shards: Map.new(shards)}}
  end

  defp validate_pos_integer!(option, value) do
    if is_integer(value) and value > 0 do
      :ok
    else
      raise ArgumentError,
            "expected #{inspect(option)} to be a positive integer, got: #{inspect(value)}"
    end
  end

  defmodule Shard do
    @moduledoc """
    A single shard of a `LRUCacheSharded` cache: a self-contained LRU cache.

    Each shard owns two ETS tables — a `:set` data table (`key ->
    {value, timestamp}`) and an `:ordered_set` order table (`timestamp -> key`)
    — plus a monotonically increasing integer counter used as the timestamp.
    The counter starts at `0` and increments by one on every recency-affecting
    operation (`put`, or a hitting `get`), giving a total, stable ordering with
    no wall-clock reads anywhere.

    All writes (insert, update, eviction, touch-on-get) are serialised through
    this process; reads may hit the data table directly.
    """

    use GenServer

    @doc """
    Starts a shard process.

    Required options: `:cache` (the owner cache name), `:index` (this shard's
    index) and `:max_size` (this shard's capacity). The process is registered
    under `LRUCacheSharded.shard_name(cache, index)`.
    """
    @spec start_link(keyword()) :: GenServer.on_start()
    def start_link(opts) do
      cache = Keyword.fetch!(opts, :cache)
      index = Keyword.fetch!(opts, :index)
      max_size = Keyword.fetch!(opts, :max_size)

      GenServer.start_link(
        __MODULE__,
        %{cache: cache, index: index, max_size: max_size},
        name: LRUCacheSharded.shard_name(cache, index)
      )
    end

    @impl GenServer
    def init(%{cache: cache, index: index, max_size: max_size}) do
      data = LRUCacheSharded.shard_data_table(cache, index)
      order = LRUCacheSharded.shard_order_table(cache, index)

      :ets.new(data, [:set, :named_table, :public, read_concurrency: true])
      :ets.new(order, [:ordered_set, :named_table, :protected])

      {:ok, %{data: data, order: order, max_size: max_size, counter: 0}}
    end

    @impl GenServer
    def handle_call({:put, key, value}, _from, state) do
      {:reply, :ok, do_put(state, key, value)}
    end

    def handle_call({:touch, key}, _from, state) do
      {:reply, :ok, do_touch(state, key)}
    end

    defp do_put(state, key, value) do
      %{data: data, order: order, max_size: max_size, counter: counter} = state

      case :ets.lookup(data, key) do
        [{^key, {_old_value, old_timestamp}}] ->
          :ets.delete(order, old_timestamp)

        [] ->
          maybe_evict(data, order, max_size)
      end

      :ets.insert(data, {key, {value, counter}})
      :ets.insert(order, {counter, key})

      %{state | counter: counter + 1}
    end

    defp do_touch(state, key) do
      %{data: data, order: order, counter: counter} = state

      case :ets.lookup(data, key) do
        [{^key, {value, old_timestamp}}] ->
          :ets.delete(order, old_timestamp)
          :ets.insert(data, {key, {value, counter}})
          :ets.insert(order, {counter, key})
          %{state | counter: counter + 1}

        [] ->
          state
      end
    end

    defp maybe_evict(data, order, max_size) do
      if :ets.info(data, :size) >= max_size do
        case :ets.first(order) do
          :"$end_of_table" ->
            :ok

          oldest_timestamp ->
            case :ets.lookup(order, oldest_timestamp) do
              [{^oldest_timestamp, victim}] ->
                :ets.delete(order, oldest_timestamp)
                :ets.delete(data, victim)

              [] ->
                :ok
            end
        end
      end

      :ok
    end
  end
end