# Reconstruct the missing typespec

In the otherwise-complete module below, the `@spec` for
`get/2` has been removed; `# TODO: @spec` holds its place.
Write that one attribute — a `@spec` for `get/2` faithful to
the arguments, guards, and every return shape the code can actually
produce. Nothing else changes.

## The module with the `@spec` for `get/2` missing

```elixir
defmodule LFUCache do
  @moduledoc """
  A Least Frequently Used (LFU) cache backed by two ETS tables.

  ## ETS tables

  | Table          | Type           | Key → Value                     | Purpose        |
  |----------------|----------------|---------------------------------|----------------|
  | `<name>_data`  | `:set`         | `key → {value, frequency, seq}` | O(1) lookup    |
  | `<name>_order` | `:ordered_set` | `{frequency, seq} → key`        | O(log n) evict |

  Eviction removes the entry with the smallest `{frequency, seq}` composite key.
  Because `frequency` is compared first, the *least frequently used* entry goes
  first; ties on frequency fall back to the smallest `seq`, i.e. the *least
  recently used* among equally-frequent entries.

  `seq` is a monotonically increasing integer counter kept in the GenServer
  state — never a wall-clock value — so ordering is deterministic and fully
  testable without any clock mocking. Every access (get, put-insert,
  put-update) draws a fresh `seq`.

  All mutations are serialised through the GenServer; reads consult ETS
  directly first, then bump the frequency through the server.
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
  Start and link an `LFUCache` process.

  ## Options

  * `:name` (required) – atom used to register the process and derive the ETS
    table names (`<name>_data` and `<name>_order`).
  * `:max_size` (required) – maximum number of entries; a positive integer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Look up `key`. Returns `{:ok, value}` (and increments the entry's frequency)
  on a hit, or `:miss` when the key is absent.
  """
  # TODO: @spec
  def get(name, key) do
    case :ets.lookup(data_table_name(name), key) do
      [{^key, {value, _freq, _seq}}] ->
        GenServer.call(name, {:touch, key})
        {:ok, value}

      [] ->
        :miss
    end
  end

  @doc """
  Insert or update `key` with `value`.

  A new entry starts at frequency 1. Updating an existing key refreshes its
  value and increments its frequency. When the cache is full and the key is
  new, the least-frequently-used entry (LRU tie-break) is evicted first.
  Always returns `:ok`.
  """
  @spec put(name(), key(), value()) :: :ok
  def put(name, key, value) do
    GenServer.call(name, {:put, key, value})
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    # A missing :max_size fails like an invalid one — ArgumentError, not the
    # KeyError a fetch! would raise (the contract reserves that for :name).
    max_size =
      case Keyword.fetch(opts, :max_size) do
        {:ok, value} -> value
        :error -> raise ArgumentError, ":max_size is required"
      end

    unless is_integer(max_size) and max_size > 0 do
      raise ArgumentError, ":max_size must be a positive integer, got: #{inspect(max_size)}"
    end

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

    state = %{
      data_table: data_table,
      order_table: order_table,
      max_size: max_size,
      counter: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:touch, key}, _from, state) do
    case :ets.lookup(state.data_table, key) do
      [{^key, {value, freq, seq}}] ->
        {new_seq, state} = next_counter(state)
        :ets.delete(state.order_table, {freq, seq})
        :ets.insert(state.order_table, {{freq + 1, new_seq}, key})
        :ets.insert(state.data_table, {key, {value, freq + 1, new_seq}})
        {:reply, :ok, state}

      [] ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:put, key, value}, _from, state) do
    state =
      case :ets.lookup(state.data_table, key) do
        [{^key, {_old_value, freq, seq}}] ->
          {new_seq, state} = next_counter(state)
          :ets.delete(state.order_table, {freq, seq})
          :ets.insert(state.order_table, {{freq + 1, new_seq}, key})
          :ets.insert(state.data_table, {key, {value, freq + 1, new_seq}})
          state

        [] ->
          state = maybe_evict(state)
          {new_seq, state} = next_counter(state)
          :ets.insert(state.order_table, {{1, new_seq}, key})
          :ets.insert(state.data_table, {key, {value, 1, new_seq}})
          state
      end

    {:reply, :ok, state}
  end

  defp next_counter(%{counter: c} = state), do: {c + 1, %{state | counter: c + 1}}

  defp maybe_evict(state) do
    if :ets.info(state.data_table, :size) >= state.max_size do
      # Smallest composite key = lowest frequency, LRU tie-break.
      victim_composite = :ets.first(state.order_table)
      [{^victim_composite, victim_key}] = :ets.lookup(state.order_table, victim_composite)
      :ets.delete(state.order_table, victim_composite)
      :ets.delete(state.data_table, victim_key)
    end

    state
  end

  defp data_table_name(name), do: :"#{name}_data"
  defp order_table_name(name), do: :"#{name}_order"
end
```

Reply with the `@spec` attribute alone, however many lines it needs —
not the module.
