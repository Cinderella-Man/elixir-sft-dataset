defmodule WeightedLRUCache do
  @moduledoc """
  A cost/weight-bounded LRU cache backed by ETS and owned by a `GenServer`.

  Unlike a cache that caps the number of resident entries, this cache caps the
  *total weight* of all entries. Each entry carries an explicit positive integer
  weight (bytes, cost units, ...) and the sum of the weights of all resident
  entries is guaranteed never to exceed `:max_weight`.

  ## Design

  Two ETS tables are owned by the `GenServer` process:

    * a `:set` table mapping `key -> {value, weight, timestamp}`, giving O(1)
      lookups that may be performed directly by the calling process;
    * an `:ordered_set` table mapping `timestamp -> key`, whose first key is
      always the least recently used entry, giving O(log n) eviction.

  Recency is expressed with a monotonically increasing integer counter held in
  the `GenServer` state rather than a wall clock, so ordering is deterministic
  and testable without mocking time.

  All mutations (`put/4`, eviction and the touch performed on a hit) are routed
  through the `GenServer` so that writes are serialised; reads hit ETS directly.

  Eviction removes whole entries only, and a single `put/4` may evict several
  entries in a row to make room. There is no TTL and no background cleanup.

  ## Example

      iex> {:ok, _pid} = WeightedLRUCache.start_link(name: :demo, max_weight: 10)
      iex> WeightedLRUCache.put(:demo, :a, "alpha", 6)
      :ok
      iex> WeightedLRUCache.put(:demo, :b, "bravo", 6)
      :ok
      iex> WeightedLRUCache.get(:demo, :a)
      :miss
      iex> WeightedLRUCache.weight(:demo)
      6
  """

  use GenServer

  @typedoc "The registered name of a cache, used for the process and its ETS tables."
  @type name :: atom()

  @typedoc "A cache key. Any term."
  @type key :: term()

  @typedoc "A cached value. Any term."
  @type value :: term()

  @typedoc "The cost of an entry. Always a positive integer."
  @type weight :: pos_integer()

  defstruct [:name, :main, :order, :max_weight, total_weight: 0, clock: 0]

  @typep state :: %__MODULE__{
           name: name(),
           main: :ets.table(),
           order: :ets.table(),
           max_weight: pos_integer(),
           total_weight: non_neg_integer(),
           clock: non_neg_integer()
         }

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Starts a cache process.

  ## Options

    * `:name` (required) - an atom used to register the process and to derive the
      names of the two ETS tables.
    * `:max_weight` (required) - a positive integer, the total weight budget.

  Raises `ArgumentError` if either option is missing or invalid.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)
    max_weight = Keyword.fetch!(opts, :max_weight)

    unless is_atom(name) and not is_nil(name) do
      raise ArgumentError, "expected :name to be an atom, got: #{inspect(name)}"
    end

    unless is_integer(max_weight) and max_weight > 0 do
      raise ArgumentError,
            "expected :max_weight to be a positive integer, got: #{inspect(max_weight)}"
    end

    GenServer.start_link(__MODULE__, {name, max_weight}, name: name)
  end

  @doc """
  Fetches the value stored under `key`.

  Returns `{:ok, value}` on a hit, `:miss` otherwise. A hit refreshes the
  entry's recency, making it the most recently used entry.

  The lookup itself is performed directly against ETS by the calling process;
  only the recency refresh is sent to the owning `GenServer`.
  """
  @spec get(name(), key()) :: {:ok, value()} | :miss
  def get(name, key) when is_atom(name) do
    case :ets.lookup(main_table(name), key) do
      [{^key, {value, _weight, _timestamp}}] ->
        GenServer.cast(name, {:touch, key})
        {:ok, value}

      [] ->
        :miss
    end
  end

  @doc """
  Inserts or updates the entry stored under `key` with the given `weight`.

  Returns:

    * `{:error, :invalid_weight}` if `weight` is not a positive integer; nothing
      is changed.
    * `{:error, :too_large}` if `weight` on its own exceeds `max_weight`, since
      the entry could never fit; nothing is changed and nothing is evicted.
    * `:ok` otherwise. Least recently used entries are evicted one at a time
      until the new entry fits within the budget, and the entry becomes the most
      recently used one.

  Updating an existing key is treated as a replacement: the old weight is
  released first, then the entry is re-inserted as the most recently used entry,
  which may itself evict *other* entries.
  """
  @spec put(name(), key(), value(), weight()) :: :ok | {:error, :invalid_weight | :too_large}
  def put(name, key, value, weight) when is_atom(name) do
    if is_integer(weight) and weight > 0 do
      GenServer.call(name, {:put, key, value, weight})
    else
      {:error, :invalid_weight}
    end
  end

  @doc """
  Returns the current total weight of all resident entries.

  The result is always between `0` and the configured `max_weight`.
  """
  @spec weight(name()) :: non_neg_integer()
  def weight(name) when is_atom(name) do
    GenServer.call(name, :weight)
  end

  # ----------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------

  @impl GenServer
  def init({name, max_weight}) do
    main = :ets.new(main_table(name), [:set, :protected, :named_table, read_concurrency: true])
    order = :ets.new(order_table(name), [:ordered_set, :protected, :named_table])

    {:ok, %__MODULE__{name: name, main: main, order: order, max_weight: max_weight}}
  end

  @impl GenServer
  def handle_call({:put, key, value, weight}, _from, state) do
    cond do
      weight > state.max_weight ->
        {:reply, {:error, :too_large}, state}

      true ->
        state =
          state
          |> delete_entry(key)
          |> evict_until_fits(weight)
          |> insert_entry(key, value, weight)

        {:reply, :ok, state}
    end
  end

  def handle_call(:weight, _from, state) do
    {:reply, state.total_weight, state}
  end

  @impl GenServer
  def handle_cast({:touch, key}, state) do
    case :ets.lookup(state.main, key) do
      [{^key, {value, weight, timestamp}}] ->
        :ets.delete(state.order, timestamp)
        {timestamp, state} = tick(state)
        :ets.insert(state.main, {key, {value, weight, timestamp}})
        :ets.insert(state.order, {timestamp, key})
        {:noreply, state}

      [] ->
        {:noreply, state}
    end
  end

  # ----------------------------------------------------------------------------
  # Internal helpers
  # ----------------------------------------------------------------------------

  # Removes `key` if present, releasing its weight. No-op when absent.
  @spec delete_entry(state(), key()) :: state()
  defp delete_entry(state, key) do
    case :ets.lookup(state.main, key) do
      [{^key, {_value, weight, timestamp}}] ->
        :ets.delete(state.main, key)
        :ets.delete(state.order, timestamp)
        %{state | total_weight: state.total_weight - weight}

      [] ->
        state
    end
  end

  # Evicts least recently used entries one at a time until `weight` fits in the
  # remaining budget. Callers must ensure `weight <= state.max_weight`.
  @spec evict_until_fits(state(), weight()) :: state()
  defp evict_until_fits(state, weight) do
    if state.total_weight + weight <= state.max_weight do
      state
    else
      case :ets.first(state.order) do
        :"$end_of_table" ->
          state

        timestamp ->
          [{^timestamp, key}] = :ets.lookup(state.order, timestamp)

          state
          |> delete_entry(key)
          |> evict_until_fits(weight)
      end
    end
  end

  # Inserts `key` as the most recently used entry and accounts for its weight.
  @spec insert_entry(state(), key(), value(), weight()) :: state()
  defp insert_entry(state, key, value, weight) do
    {timestamp, state} = tick(state)
    :ets.insert(state.main, {key, {value, weight, timestamp}})
    :ets.insert(state.order, {timestamp, key})
    %{state | total_weight: state.total_weight + weight}
  end

  # Advances the logical clock and returns the freshly allocated timestamp.
  @spec tick(state()) :: {non_neg_integer(), state()}
  defp tick(state) do
    timestamp = state.clock + 1
    {timestamp, %{state | clock: timestamp}}
  end

  @spec main_table(name()) :: atom()
  defp main_table(name), do: :"#{name}.main"

  @spec order_table(name()) :: atom()
  defp order_table(name), do: :"#{name}.order"
end