defmodule LFUCache do
  @moduledoc """
  A Least Frequently Used (LFU) cache implemented as a `GenServer` backed by two ETS tables.

  Entries are evicted when the cache is full and a *new* key is inserted. The victim is the
  entry with the lowest access frequency; ties at that frequency are broken by evicting the
  least recently used of them.

  ## Tables

  Two named ETS tables are owned by the server, derived from the `:name` option:

    * `:"<name>_data"` — a `:set` mapping `key -> {value, frequency, seq}`. It is
      `:protected`, so any process may read it directly (`get/2` does exactly that), but
      only the server may write to it.
    * `:"<name>_order"` — an `:ordered_set` mapping `{frequency, seq} -> key`. Because Erlang
      term ordering compares the tuple element-wise, the first key of this table is always the
      least frequently used entry, with a least-recently-used tie-break. Eviction is therefore
      an O(log n) `:ets.first/1`.

  ## Recency

  Recency is a strictly monotonic integer counter (`seq`) kept in the server state — never a
  wall-clock reading. Every access (a `get/2` hit, an inserting `put/3`, or an updating
  `put/3`) draws a fresh, strictly larger `seq`; a `get/2` miss draws nothing. Ordering is thus
  total and eviction is fully deterministic for a given sequence of calls.

  ## Concurrency

  All mutations — including the frequency bump triggered by a read — are serialised through the
  server via synchronous calls, so concurrent callers observe a single well-defined
  interleaving. Reads hit ETS directly and then ask the server to record the access; if the key
  was evicted in between, the bump is a harmless no-op.

  There is no TTL, no background cleanup, and no maximum frequency.

  ## Example

      iex> {:ok, _pid} = LFUCache.start_link(name: :demo_cache, max_size: 2)
      iex> LFUCache.put(:demo_cache, :a, 1)
      :ok
      iex> LFUCache.get(:demo_cache, :a)
      {:ok, 1}
      iex> LFUCache.get(:demo_cache, :missing)
      :miss
  """

  use GenServer

  @typedoc "Any term may be used as a cache key."
  @type key :: term()

  @typedoc "Any term may be stored as a cache value."
  @type value :: term()

  defstruct [:data, :order, :max_size, :seq]

  @typep state :: %__MODULE__{
           data: :ets.tab(),
           order: :ets.tab(),
           max_size: pos_integer(),
           seq: non_neg_integer()
         }

  ## Public API

  @doc """
  Starts the cache and links it to the calling process.

  ## Options

    * `:name` (required, atom) — registers the process and derives the ETS table names
      `:"<name>_data"` and `:"<name>_order"`.
    * `:max_size` (required, positive integer) — the maximum number of entries held at once.

  Raises `ArgumentError` if `:max_size` is missing or is not a positive integer, and whatever
  `Keyword.fetch!/2` raises if `:name` is missing.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns a child specification so the cache can be dropped straight into a supervision tree.

  The given `opts` are passed verbatim to `start_link/1`.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @doc """
  Looks `key` up in the cache registered under `name`.

  Returns `{:ok, value}` on a hit, counting the read as one access: the entry's frequency is
  incremented and it becomes the most recently used entry before this function returns.

  Returns `:miss` if the key is absent. A miss changes nothing — no entry is created, no
  frequency or recency is touched, and nothing is evicted.
  """
  @spec get(atom(), key()) :: {:ok, value()} | :miss
  def get(name, key) when is_atom(name) do
    case :ets.lookup(data_table(name), key) do
      [{^key, value, _freq, _seq}] ->
        case GenServer.call(name, {:touch, key}) do
          {:ok, current} -> {:ok, current}
          :miss -> {:ok, value}
        end

      [] ->
        :miss
    end
  end

  @doc """
  Inserts or updates `key` with `value` in the cache registered under `name`.

  A brand-new key is stored with frequency `1`. An existing key has its value overwritten, its
  frequency incremented, and its recency refreshed — updating never evicts anything. Inserting
  a new key while the cache holds `max_size` entries first evicts the least frequently used
  entry (ties broken by least recently used).

  Always returns `:ok`.
  """
  @spec put(atom(), key(), value()) :: :ok
  def put(name, key, value) when is_atom(name) do
    GenServer.call(name, {:put, key, value})
  end

  ## GenServer callbacks

  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    max_size = validate_max_size(Keyword.get(opts, :max_size))

    data =
      :ets.new(data_table(name), [:set, :named_table, :protected, read_concurrency: true])

    order = :ets.new(order_table(name), [:ordered_set, :named_table, :private])

    {:ok, %__MODULE__{data: data, order: order, max_size: max_size, seq: 0}}
  end

  @impl GenServer
  def handle_call({:touch, key}, _from, state) do
    case :ets.lookup(state.data, key) do
      [{^key, value, freq, seq}] ->
        {state, new_seq} = next_seq(state)
        :ets.delete(state.order, {freq, seq})
        :ets.insert(state.data, {key, value, freq + 1, new_seq})
        :ets.insert(state.order, {{freq + 1, new_seq}, key})
        {:reply, {:ok, value}, state}

      [] ->
        {:reply, :miss, state}
    end
  end

  def handle_call({:put, key, value}, _from, state) do
    {state, new_seq} = next_seq(state)

    state =
      case :ets.lookup(state.data, key) do
        [{^key, _old_value, freq, seq}] ->
          :ets.delete(state.order, {freq, seq})
          insert(state, key, value, freq + 1, new_seq)

        [] ->
          state
          |> maybe_evict()
          |> insert(key, value, 1, new_seq)
      end

    {:reply, :ok, state}
  end

  ## Internal helpers

  @spec insert(state(), key(), value(), pos_integer(), non_neg_integer()) :: state()
  defp insert(state, key, value, freq, seq) do
    :ets.insert(state.data, {key, value, freq, seq})
    :ets.insert(state.order, {{freq, seq}, key})
    state
  end

  @spec maybe_evict(state()) :: state()
  defp maybe_evict(state) do
    if :ets.info(state.data, :size) >= state.max_size do
      case :ets.first(state.order) do
        :"$end_of_table" ->
          state

        composite ->
          case :ets.lookup(state.order, composite) do
            [{^composite, victim}] -> :ets.delete(state.data, victim)
            [] -> :ok
          end

          :ets.delete(state.order, composite)
          state
      end
    else
      state
    end
  end

  @spec next_seq(state()) :: {state(), pos_integer()}
  defp next_seq(%__MODULE__{seq: seq} = state), do: {%{state | seq: seq + 1}, seq + 1}

  @spec validate_max_size(term()) :: pos_integer()
  defp validate_max_size(max_size) when is_integer(max_size) and max_size > 0, do: max_size

  defp validate_max_size(other) do
    raise ArgumentError,
          ":max_size must be a positive integer, got: #{inspect(other)}"
  end

  @spec data_table(atom()) :: atom()
  defp data_table(name), do: :"#{name}_data"

  @spec order_table(atom()) :: atom()
  defp order_table(name), do: :"#{name}_order"
end