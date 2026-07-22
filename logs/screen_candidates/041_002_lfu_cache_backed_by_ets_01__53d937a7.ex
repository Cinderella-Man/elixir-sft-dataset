defmodule LFUCache do
  @moduledoc """
  A Least Frequently Used (LFU) cache implemented as a `GenServer` backed by two ETS tables.

  Entries are evicted based on how *often* they have been accessed rather than how recently.
  When several entries share the lowest access frequency, the one that was accessed longest
  ago is evicted first (a least-recently-used tie-break).

  ## Tables

  Two named ETS tables are owned by the server, derived from the required `:name` option:

    * `:"<name>_data"` — a `:set` mapping `key -> {value, frequency, seq}`. It is
      `:public`/readable from any process so `get/2` can read it directly without a call.
    * `:"<name>_order"` — an `:ordered_set` mapping `{frequency, seq} -> key`. Because the
      composite key sorts by frequency first and recency second, the eviction victim is
      always the first element of the table.

  ## Recency

  Recency is tracked with a strictly monotonic integer counter (`seq`) held in the server
  state — never a wall clock — so ordering is total and eviction is fully deterministic for
  a given sequence of calls.

  ## Concurrency

  Reads go straight to ETS; every mutation (inserts, updates, the frequency bump performed by
  `get/2`, and evictions) is serialised through the `GenServer` via synchronous calls.

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

  @typedoc "The name used to register the server and derive the ETS table names."
  @type name :: atom()

  @typedoc "Any term may be used as a cache key."
  @type key :: term()

  @typedoc "Any term may be used as a cached value."
  @type value :: term()

  defstruct [:data, :order, :max_size, seq: 0]

  @typep state :: %__MODULE__{
           data: atom(),
           order: atom(),
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

  Raises `ArgumentError` during initialisation when `:max_size` is missing or is not an
  integer greater than zero. A missing `:name` raises the error of `Keyword.fetch!/2`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns a child specification so the cache can be placed directly in a supervision tree.

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
  Looks up `key` in the cache named `name`.

  Returns `{:ok, value}` on a hit, counting the lookup as one access: the entry's frequency is
  incremented and it becomes the most recently used entry. The bump is committed before this
  function returns.

  Returns `:miss` when the key is absent; a miss changes nothing at all.
  """
  @spec get(name(), key()) :: {:ok, value()} | :miss
  def get(name, key) when is_atom(name) do
    case :ets.lookup(data_table(name), key) do
      [{^key, {value, _frequency, _seq}}] ->
        :ok = GenServer.call(name, {:touch, key})
        {:ok, value}

      [] ->
        :miss
    end
  end

  @doc """
  Inserts or updates `key` with `value` in the cache named `name`.

  A brand-new key starts at frequency `1`. An existing key has its value overwritten and its
  frequency incremented, and never triggers an eviction. When the key is new and the cache is
  already at `:max_size`, the least frequently used entry (least recently used among ties) is
  evicted before the insert.

  Always returns `:ok`.
  """
  @spec put(name(), key(), value()) :: :ok
  def put(name, key, value) when is_atom(name) do
    GenServer.call(name, {:put, key, value})
  end

  ## GenServer callbacks

  @impl GenServer
  @spec init(keyword()) :: {:ok, state()}
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    max_size = validate_max_size(Keyword.get(opts, :max_size))

    data = data_table(name)
    order = order_table(name)

    ^data = :ets.new(data, [:set, :named_table, :protected, read_concurrency: true])
    ^order = :ets.new(order, [:ordered_set, :named_table, :private])

    {:ok, %__MODULE__{data: data, order: order, max_size: max_size}}
  end

  @impl GenServer
  def handle_call({:touch, key}, _from, state) do
    case :ets.lookup(state.data, key) do
      [{^key, {value, frequency, seq}}] ->
        state = bump(state, key, value, frequency, seq)
        {:reply, :ok, state}

      [] ->
        # The entry vanished between the caller's direct ETS read and this call: no-op.
        {:reply, :ok, state}
    end
  end

  def handle_call({:put, key, value}, _from, state) do
    case :ets.lookup(state.data, key) do
      [{^key, {_old_value, frequency, seq}}] ->
        {:reply, :ok, bump(state, key, value, frequency, seq)}

      [] ->
        state = state |> maybe_evict() |> insert_new(key, value)
        {:reply, :ok, state}
    end
  end

  ## Internals

  @spec validate_max_size(term()) :: pos_integer()
  defp validate_max_size(max_size) when is_integer(max_size) and max_size > 0, do: max_size

  defp validate_max_size(max_size) do
    raise ArgumentError,
          ":max_size must be a positive integer, got: #{inspect(max_size)}"
  end

  # Replaces the entry's value, increments its frequency and makes it most recently used.
  @spec bump(state(), key(), value(), pos_integer(), non_neg_integer()) :: state()
  defp bump(state, key, value, frequency, seq) do
    {state, next_seq} = next_seq(state)
    :ets.delete(state.order, {frequency, seq})
    :ets.insert(state.data, {key, {value, frequency + 1, next_seq}})
    :ets.insert(state.order, {{frequency + 1, next_seq}, key})
    state
  end

  # Inserts a brand-new entry at frequency 1 as the most recently used entry.
  @spec insert_new(state(), key(), value()) :: state()
  defp insert_new(state, key, value) do
    {state, seq} = next_seq(state)
    :ets.insert(state.data, {key, {value, 1, seq}})
    :ets.insert(state.order, {{1, seq}, key})
    state
  end

  # Drops the least frequently used entry (LRU tie-break) when the cache is full.
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

  @spec data_table(name()) :: atom()
  defp data_table(name), do: :"#{name}_data"

  @spec order_table(name()) :: atom()
  defp order_table(name), do: :"#{name}_order"
end