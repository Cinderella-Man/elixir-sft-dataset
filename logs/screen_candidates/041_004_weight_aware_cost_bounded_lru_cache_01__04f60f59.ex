defmodule WeightedLRUCache do
  @moduledoc """
  A cost/weight-bounded LRU cache implemented as a `GenServer` backed by ETS.

  Unlike a count-bounded LRU cache, this cache caps the *total weight* of all
  resident entries rather than their number. Every entry carries an explicit
  positive integer weight (bytes, cost units, …). The cache guarantees that the
  sum of the weights of all resident entries never exceeds `max_weight`.

  ## Design

    * Two ETS tables are owned by the `GenServer`:
      * a `:set` table mapping `key -> {value, weight, timestamp}` for O(1)
        lookups;
      * an `:ordered_set` table mapping `timestamp -> key`, used to locate the
        least-recently-used entry for eviction.
    * Recency is tracked with a monotonically increasing integer counter held in
      the `GenServer` state, so ordering is deterministic and testable without
      mocking a clock.
    * The running total weight is kept in the `GenServer` state and stays exactly
      in sync as entries are inserted, updated, and evicted.
    * All mutations (put, eviction, touch-on-get) are serialised through the
      `GenServer`. Reads may hit the ETS `:set` table directly.

  There is no TTL and no background cleanup: entries only leave the cache when
  they are evicted to make room, or replaced by a newer value for the same key.
  """

  use GenServer

  @typedoc "A cache key. Any term is accepted."
  @type key :: term()

  @typedoc "A cached value. Any term is accepted."
  @type value :: term()

  @typedoc "An entry weight — a positive integer."
  @type weight :: pos_integer()

  ## Public API

  @doc """
  Starts the cache process linked to the caller.

  ## Options

    * `:name` (required) — an atom used to register the process and to derive the
      names of the two backing ETS tables.
    * `:max_weight` (required) — a positive integer, the total weight budget that
      resident entries may never collectively exceed.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)
    max_weight = Keyword.fetch!(opts, :max_weight)

    unless is_atom(name) do
      raise ArgumentError, ":name must be an atom, got: #{inspect(name)}"
    end

    unless is_integer(max_weight) and max_weight > 0 do
      raise ArgumentError,
            ":max_weight must be a positive integer, got: #{inspect(max_weight)}"
    end

    GenServer.start_link(__MODULE__, {name, max_weight}, name: name)
  end

  @doc """
  Fetches the value stored under `key`.

  Returns `{:ok, value}` on a hit (refreshing the entry's recency so it becomes
  the most-recently-used entry) or `:miss` when the key is absent.
  """
  @spec get(atom(), key()) :: {:ok, value()} | :miss
  def get(name, key) do
    case :ets.lookup(set_table(name), key) do
      [{^key, value, _weight, _timestamp}] ->
        GenServer.cast(name, {:touch, key})
        {:ok, value}

      [] ->
        :miss
    end
  end

  @doc """
  Inserts or updates the entry stored under `key` with the given `weight`.

  Return values encode the failure semantics:

    * `{:error, :invalid_weight}` if `weight` is not a positive integer; nothing
      changes.
    * `{:error, :too_large}` if `weight` alone exceeds `max_weight` (the entry
      could never fit); nothing changes and nothing is evicted.
    * `:ok` otherwise. Before inserting, least-recently-used entries are evicted
      one at a time until the new entry fits within the budget. Updating an
      existing key replaces it: its old weight is released first, then it is
      re-inserted as the most-recently-used entry (which may itself evict *other*
      entries).
  """
  @spec put(atom(), key(), value(), weight()) ::
          :ok | {:error, :invalid_weight | :too_large}
  def put(name, key, value, weight) do
    GenServer.call(name, {:put, key, value, weight})
  end

  @doc """
  Returns the current total resident weight of the cache.
  """
  @spec weight(atom()) :: non_neg_integer()
  def weight(name) do
    GenServer.call(name, :weight)
  end

  ## GenServer callbacks

  @impl GenServer
  def init({name, max_weight}) do
    set = set_table(name)
    ord = ord_table(name)

    :ets.new(set, [:set, :named_table, :protected, read_concurrency: true])
    :ets.new(ord, [:ordered_set, :named_table, :protected, read_concurrency: true])

    state = %{
      set: set,
      ord: ord,
      max_weight: max_weight,
      counter: 0,
      total_weight: 0
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:put, _key, _value, weight}, _from, state)
      when not (is_integer(weight) and weight > 0) do
    {:reply, {:error, :invalid_weight}, state}
  end

  def handle_call({:put, _key, _value, weight}, _from, %{max_weight: max} = state)
      when weight > max do
    {:reply, {:error, :too_large}, state}
  end

  def handle_call({:put, key, value, weight}, _from, state) do
    state = release(state, key)
    state = evict_until_fits(state, weight)
    state = insert(state, key, value, weight)
    {:reply, :ok, state}
  end

  def handle_call(:weight, _from, state) do
    {:reply, state.total_weight, state}
  end

  @impl GenServer
  def handle_cast({:touch, key}, state) do
    case :ets.lookup(state.set, key) do
      [{^key, value, weight, timestamp}] ->
        :ets.delete(state.ord, timestamp)
        {ts, state} = next_timestamp(state)
        :ets.insert(state.set, {key, value, weight, ts})
        :ets.insert(state.ord, {ts, key})
        {:noreply, state}

      [] ->
        {:noreply, state}
    end
  end

  ## Internal helpers

  # Removes an existing entry (if present) and releases its weight from the
  # running total. A no-op when the key is absent.
  @spec release(map(), key()) :: map()
  defp release(state, key) do
    case :ets.lookup(state.set, key) do
      [{^key, _value, weight, timestamp}] ->
        :ets.delete(state.set, key)
        :ets.delete(state.ord, timestamp)
        %{state | total_weight: state.total_weight - weight}

      [] ->
        state
    end
  end

  # Evicts least-recently-used entries one at a time until `incoming` weight
  # fits within the budget. Terminates because emptying the cache drives the
  # total to 0 and `incoming <= max_weight` is guaranteed by the caller.
  @spec evict_until_fits(map(), weight()) :: map()
  defp evict_until_fits(%{total_weight: total, max_weight: max} = state, incoming)
       when total + incoming <= max do
    _ = incoming
    state
  end

  defp evict_until_fits(state, incoming) do
    case :ets.first(state.ord) do
      :"$end_of_table" ->
        state

      timestamp ->
        [{^timestamp, key}] = :ets.lookup(state.ord, timestamp)
        state = release(state, key)
        evict_until_fits(state, incoming)
    end
  end

  # Inserts a fresh entry as the most-recently-used and adds its weight to the
  # running total.
  @spec insert(map(), key(), value(), weight()) :: map()
  defp insert(state, key, value, weight) do
    {ts, state} = next_timestamp(state)
    :ets.insert(state.set, {key, value, weight, ts})
    :ets.insert(state.ord, {ts, key})
    %{state | total_weight: state.total_weight + weight}
  end

  # Produces the next monotonically increasing timestamp and the updated state.
  @spec next_timestamp(map()) :: {non_neg_integer(), map()}
  defp next_timestamp(state) do
    ts = state.counter + 1
    {ts, %{state | counter: ts}}
  end

  @spec set_table(atom()) :: atom()
  defp set_table(name), do: :"#{name}.set"

  @spec ord_table(atom()) :: atom()
  defp ord_table(name), do: :"#{name}.ord"
end