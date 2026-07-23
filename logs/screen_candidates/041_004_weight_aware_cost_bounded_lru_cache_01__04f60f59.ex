defmodule WeightedLRUCache do
  @moduledoc """
  A cost/weight-bounded LRU cache implemented as a `GenServer` backed by ETS.

  Unlike a classic LRU cache that caps the *number* of resident entries, this
  cache caps the *total weight* of all entries. Every entry carries an explicit
  positive integer `weight` (bytes, cost units, …) and the cache guarantees the
  sum of the weights of all resident entries never exceeds `max_weight`.

  ## Design

    * Two ETS tables are owned by the `GenServer`:
      * a `:set` table mapping `key -> {value, weight, timestamp}` for O(1)
        lookups (reads may hit this table directly), and
      * an `:ordered_set` table mapping `timestamp -> key`, used to find the
        least-recently-used entry during eviction.
    * A monotonically increasing integer counter in the process state acts as
      the logical clock, so recency ordering is deterministic and testable
      without mocking wall-clock time.
    * The running total weight is tracked in the process state and kept exactly
      in sync as entries are inserted, updated, and evicted.
    * All mutations — `put/4`, eviction, and touch-on-`get/2` — are serialised
      through the `GenServer`. There is no TTL and no background cleanup.

  ## Eviction

  When inserting would exceed `max_weight`, least-recently-used entries are
  evicted one whole entry at a time until the incoming entry fits. Updating an
  existing key is treated as a replacement: its old weight is released first,
  then it is re-inserted as the most-recently-used entry (which may itself
  trigger eviction of *other* entries).
  """

  use GenServer

  @typedoc "The registered name of a cache process (and ETS table namespace)."
  @type name :: atom()

  defstruct [:name, :set_table, :ord_table, :max_weight, total: 0, counter: 0]

  @typep state :: %__MODULE__{
           name: name(),
           set_table: atom(),
           ord_table: atom(),
           max_weight: pos_integer(),
           total: non_neg_integer(),
           counter: non_neg_integer()
         }

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Starts the cache process linked to the caller.

  ## Options

    * `:name` (required) — an atom used to register the process and to derive
      the names of the two ETS tables.
    * `:max_weight` (required) — a positive integer, the total weight budget.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Looks up `key` in the cache named `name`.

  Returns `{:ok, value}` on a hit (which refreshes the entry's recency) or
  `:miss` when the key is absent.
  """
  @spec get(name(), term()) :: {:ok, term()} | :miss
  def get(name, key) do
    case :ets.lookup(set_table_name(name), key) do
      [{^key, {value, _weight, _ts}}] ->
        _ = GenServer.call(name, {:touch, key})
        {:ok, value}

      [] ->
        :miss
    end
  end

  @doc """
  Inserts or updates `key` with `value` and the given `weight`.

  Return values:

    * `{:error, :invalid_weight}` — `weight` is not a positive integer; the
      cache is unchanged.
    * `{:error, :too_large}` — `weight` alone exceeds `max_weight`, so the entry
      could never fit; the cache is unchanged and nothing is evicted.
    * `:ok` — the entry was stored. Least-recently-used entries were evicted one
      at a time beforehand if necessary to stay within the budget.

  Updating an existing key releases its old weight first, then re-inserts it as
  the most-recently-used entry.
  """
  @spec put(name(), term(), term(), term()) :: :ok | {:error, :invalid_weight | :too_large}
  def put(name, key, value, weight) do
    GenServer.call(name, {:put, key, value, weight})
  end

  @doc """
  Returns the current total resident weight of the cache named `name`.
  """
  @spec weight(name()) :: non_neg_integer()
  def weight(name) do
    GenServer.call(name, :weight)
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────────

  @impl true
  @spec init(keyword()) :: {:ok, state()} | {:stop, term()}
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    max_weight = Keyword.fetch!(opts, :max_weight)

    if is_integer(max_weight) and max_weight > 0 do
      set_table = set_table_name(name)
      ord_table = ord_table_name(name)

      :ets.new(set_table, [:set, :protected, :named_table, read_concurrency: true])
      :ets.new(ord_table, [:ordered_set, :protected, :named_table])

      state = %__MODULE__{
        name: name,
        set_table: set_table,
        ord_table: ord_table,
        max_weight: max_weight
      }

      {:ok, state}
    else
      {:stop, {:invalid_max_weight, max_weight}}
    end
  end

  @impl true
  def handle_call({:put, key, value, weight}, _from, state) do
    cond do
      not (is_integer(weight) and weight > 0) ->
        {:reply, {:error, :invalid_weight}, state}

      weight > state.max_weight ->
        {:reply, {:error, :too_large}, state}

      true ->
        state =
          state
          |> release_if_present(key)
          |> evict_until_fits(weight)
          |> insert_entry(key, value, weight)

        {:reply, :ok, state}
    end
  end

  def handle_call({:touch, key}, _from, state) do
    case :ets.lookup(state.set_table, key) do
      [{^key, {value, weight, old_ts}}] ->
        :ets.delete(state.ord_table, old_ts)
        ts = state.counter + 1
        :ets.insert(state.set_table, {key, {value, weight, ts}})
        :ets.insert(state.ord_table, {ts, key})
        {:reply, :ok, %{state | counter: ts}}

      [] ->
        {:reply, :ok, state}
    end
  end

  def handle_call(:weight, _from, state) do
    {:reply, state.total, state}
  end

  # ── Internal helpers ────────────────────────────────────────────────────────

  # Removes `key` if present, releasing its weight from the running total.
  @spec release_if_present(state(), term()) :: state()
  defp release_if_present(state, key) do
    case :ets.lookup(state.set_table, key) do
      [{^key, {_value, weight, ts}}] ->
        :ets.delete(state.set_table, key)
        :ets.delete(state.ord_table, ts)
        %{state | total: state.total - weight}

      [] ->
        state
    end
  end

  # Evicts least-recently-used entries until `incoming` fits within the budget.
  @spec evict_until_fits(state(), pos_integer()) :: state()
  defp evict_until_fits(state, incoming) do
    if state.total + incoming > state.max_weight do
      state |> evict_lru() |> evict_until_fits(incoming)
    else
      state
    end
  end

  # Evicts the single least-recently-used entry (smallest timestamp).
  @spec evict_lru(state()) :: state()
  defp evict_lru(state) do
    case :ets.first(state.ord_table) do
      :"$end_of_table" ->
        state

      ts ->
        [{^ts, key}] = :ets.lookup(state.ord_table, ts)
        :ets.delete(state.ord_table, ts)

        released =
          case :ets.lookup(state.set_table, key) do
            [{^key, {_value, weight, _ts}}] ->
              :ets.delete(state.set_table, key)
              weight

            [] ->
              0
          end

        %{state | total: state.total - released}
    end
  end

  # Inserts a fresh entry as the most-recently-used, adding its weight.
  @spec insert_entry(state(), term(), term(), pos_integer()) :: state()
  defp insert_entry(state, key, value, weight) do
    ts = state.counter + 1
    :ets.insert(state.set_table, {key, {value, weight, ts}})
    :ets.insert(state.ord_table, {ts, key})
    %{state | counter: ts, total: state.total + weight}
  end

  @spec set_table_name(name()) :: atom()
  defp set_table_name(name), do: :"#{name}.WeightedLRUCache.Set"

  @spec ord_table_name(name()) :: atom()
  defp ord_table_name(name), do: :"#{name}.WeightedLRUCache.Ord"
end