defmodule LRUCache do
  @moduledoc """
  A Least Recently Used (LRU) cache implemented as a `GenServer` backed by two ETS tables.

  ## Design

  Two ETS tables are owned by the cache process and named deterministically from the
  required `:name` option, so they are stable and inspectable:

    * `:"<name>_data"` — a `:set` table mapping `key -> {value, counter}`. It is a
      `:protected` table with `read_concurrency`, so any process may read it directly
      (this is what makes `get/2` lookups fast) while only the owner writes to it.
    * `:"<name>_order"` — an `:ordered_set` table mapping `counter -> key`. Because the
      keys are integers, the least-recently-used entry is `:ets.first/1`, found in
      O(log n). Only the owner ever touches this table.

  Recency is tracked with a strictly monotonic integer counter held in the server state —
  never a wall-clock value — so ordering is deterministic and the cache can be tested
  without mocking any clock. Every touch (a `put/3`, an overwrite, or a hit on `get/2`)
  consumes a fresh, strictly larger counter and deletes the key's stale ordering row, so a
  key is never present twice in the order table.

  All mutations — inserts, evictions, and the promotion performed after a successful read —
  are serialised through the GenServer with synchronous calls. Consequently, when `put/3`
  returns `:ok` the write is already visible, and when `get/2` returns `{:ok, value}` the
  promotion has already been applied.

  There is no TTL and no background cleanup: entries leave the cache only through LRU
  eviction, and nothing is persisted across a restart.

  ## Example

      iex> {:ok, _pid} = LRUCache.start_link(name: :demo_cache, max_size: 2)
      iex> LRUCache.put(:demo_cache, :a, 1)
      :ok
      iex> LRUCache.put(:demo_cache, :b, 2)
      :ok
      iex> LRUCache.get(:demo_cache, :a)
      {:ok, 1}
      iex> LRUCache.put(:demo_cache, :c, 3)
      :ok
      iex> LRUCache.get(:demo_cache, :b)
      :miss

  """

  use GenServer

  @typedoc "The registered name of a cache; also the base for its ETS table names."
  @type name :: atom()

  @typedoc "Any term may be used as a cache key."
  @type key :: term()

  @typedoc "Any term may be stored as a cache value, including `nil` and `false`."
  @type value :: term()

  @typedoc "Internal server state."
  @type state :: %{
          data: atom(),
          order: atom(),
          max_size: pos_integer(),
          size: non_neg_integer(),
          counter: integer()
        }

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Returns a supervisor child specification for a cache, using `:name` as the child `id`.

  The `opts` are passed verbatim to `start_link/1`, so `:name` and `:max_size` are both
  required here as well.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
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

  @doc """
  Starts and links an LRU cache process.

  ## Options

    * `:name` (required, atom) — registers the process under this name and derives the
      names of the backing ETS tables (`:"<name>_data"` and `:"<name>_order"`).
    * `:max_size` (required, positive integer) — the maximum number of entries held at
      once. A `max_size` of `1` is legal: every insert of a new key evicts the resident
      entry.

  A missing option fails with a `KeyError`; a `:max_size` that is not a positive integer
  fails with an `ArgumentError` raised from the process's initialisation.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)
    max_size = Keyword.fetch!(opts, :max_size)

    GenServer.start_link(__MODULE__, {name, max_size}, name: name)
  end

  @doc """
  Looks up `key` in the cache registered under `name`.

  Returns `{:ok, value}` when the key is present — including when the stored value is
  `nil` or `false`, since presence is decided by the key existing and never by the value
  being truthy. Returns the bare atom `:miss` when the key is absent.

  A hit promotes the entry to most-recently-used before returning. A miss changes nothing:
  it creates no entry, evicts nothing, and does not disturb the ordering of other keys.
  """
  @spec get(name(), key()) :: {:ok, value()} | :miss
  def get(name, key) when is_atom(name) do
    case :ets.lookup(data_table(name), key) do
      [{^key, {value, counter}}] ->
        :ok = GenServer.call(name, {:touch, key, counter})
        {:ok, value}

      [] ->
        :miss
    end
  end

  @doc """
  Inserts or updates `key` with `value` in the cache registered under `name`.

  Always returns `:ok`.

    * If the key already exists, its value is replaced and the entry is promoted to
      most-recently-used. The size is unchanged and nothing is evicted, even at capacity —
      overwriting a key never evicts.
    * If the key is new and the cache is below `max_size`, the entry is inserted and
      becomes most-recently-used.
    * If the key is new and the cache is exactly at `max_size`, the single
      least-recently-used entry is evicted first, then the new entry is inserted; the size
      stays at `max_size`.
  """
  @spec put(name(), key(), value()) :: :ok
  def put(name, key, value) when is_atom(name) do
    GenServer.call(name, {:put, key, value})
  end

  # ----------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------

  @impl GenServer
  @spec init({name(), term()}) :: {:ok, state()}
  def init({name, max_size}) do
    unless is_atom(name) do
      raise ArgumentError, "expected :name to be an atom, got: #{inspect(name)}"
    end

    unless is_integer(max_size) and max_size > 0 do
      raise ArgumentError,
            "expected :max_size to be a positive integer, got: #{inspect(max_size)}"
    end

    data = data_table(name)
    order = order_table(name)

    ^data = :ets.new(data, [:set, :protected, :named_table, read_concurrency: true])
    ^order = :ets.new(order, [:ordered_set, :private, :named_table])

    {:ok, %{data: data, order: order, max_size: max_size, size: 0, counter: 0}}
  end

  @impl GenServer
  def handle_call({:put, key, value}, _from, state) do
    state =
      case :ets.lookup(state.data, key) do
        [{^key, {_old_value, old_counter}}] ->
          # Overwrite: replace the value and promote. Size is unchanged; nothing is evicted.
          :ets.delete(state.order, old_counter)
          store(state, key, value)

        [] ->
          state
          |> maybe_evict()
          |> store(key, value)
          |> Map.update!(:size, &(&1 + 1))
      end

    {:reply, :ok, state}
  end

  def handle_call({:touch, key, counter}, _from, state) do
    # A direct ETS read in `get/2` can race with a concurrent eviction, so the key (or its
    # counter) may have changed or vanished in the meantime. In that case, do nothing.
    case :ets.lookup(state.data, key) do
      [{^key, {value, ^counter}}] ->
        :ets.delete(state.order, counter)
        {:reply, :ok, store(state, key, value)}

      _other ->
        {:reply, :ok, state}
    end
  end

  # ----------------------------------------------------------------------------
  # Internal helpers
  # ----------------------------------------------------------------------------

  # Writes `key -> {value, counter}` with a fresh, strictly larger counter and records the
  # matching ordering row. The caller must already have removed any stale ordering row.
  @spec store(state(), key(), value()) :: state()
  defp store(state, key, value) do
    counter = state.counter + 1

    :ets.insert(state.data, {key, {value, counter}})
    :ets.insert(state.order, {counter, key})

    %{state | counter: counter}
  end

  # Evicts the single least-recently-used entry when the cache is exactly at capacity.
  @spec maybe_evict(state()) :: state()
  defp maybe_evict(%{size: size, max_size: max_size} = state) when size >= max_size do
    case :ets.first(state.order) do
      :"$end_of_table" ->
        state

      oldest_counter ->
        case :ets.lookup(state.order, oldest_counter) do
          [{^oldest_counter, oldest_key}] ->
            :ets.delete(state.order, oldest_counter)
            :ets.delete(state.data, oldest_key)
            %{state | size: state.size - 1}

          [] ->
            state
        end
    end
  end

  defp maybe_evict(state), do: state

  @spec data_table(name()) :: atom()
  defp data_table(name), do: :"#{name}_data"

  @spec order_table(name()) :: atom()
  defp order_table(name), do: :"#{name}_order"
end