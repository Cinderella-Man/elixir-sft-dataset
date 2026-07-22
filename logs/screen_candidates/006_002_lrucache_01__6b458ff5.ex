defmodule LRUCache do
  @moduledoc """
  A fixed-capacity least-recently-used (LRU) cache implemented as a `GenServer`.

  Unlike a TTL-based cache that bounds memory by time, `LRUCache` bounds memory by
  a fixed **maximum number of entries**. When a new key is inserted while the cache
  is already at capacity, the single least-recently-used entry — the one accessed
  (read or written) longest ago — is evicted **before** the new entry is stored.

  Entries are held as `%{key => %{value: value, access_ts: integer}}`. Both `get/2`
  (on a hit) and `put/3` (always) count as accesses that refresh the timestamp of
  the touched key; `delete/2` does not. Eviction scans the entry map with
  `Enum.min_by/2`, which is O(n) per eviction — an intentional, acceptable trade-off
  for this design.

  There is no TTL and no periodic sweep: with a fixed capacity, memory is bounded by
  construction. The `:clock` function is used solely to order accesses.
  """

  use GenServer

  @typedoc "The user-facing cache key."
  @type key :: term()

  @typedoc "The user-facing cache value."
  @type value :: term()

  @typedoc "A running cache process reference (pid or registered name)."
  @type server :: GenServer.server()

  ## Public API

  @doc """
  Starts the cache process.

  Options:

    * `:name` — optional process registration name.
    * `:capacity` — required positive integer, the maximum number of entries.
    * `:clock` — zero-arity function returning a monotonically-increasing integer.
      Defaults to `fn -> System.monotonic_time() end`.

  Raises `ArgumentError` in the calling process when `:capacity` is not a positive
  integer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    capacity = Keyword.get(opts, :capacity)

    unless is_integer(capacity) and capacity > 0 do
      raise ArgumentError,
            "expected :capacity to be a positive integer, got: #{inspect(capacity)}"
    end

    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time() end)
    init_arg = %{capacity: capacity, clock: clock}

    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, init_arg, name: name)
      :error -> GenServer.start_link(__MODULE__, init_arg)
    end
  end

  @doc """
  Stores `value` under `key`.

  If `key` already exists, its value is overwritten and its access timestamp is
  refreshed, making it most-recently-used; this never evicts another key. If `key`
  is new and the cache is at capacity, the single least-recently-used entry is
  evicted before the new entry is inserted. Always returns `:ok`.
  """
  @spec put(server(), key(), value()) :: :ok
  def put(server, key, value) do
    GenServer.call(server, {:put, key, value})
  end

  @doc """
  Looks up `key`.

  On a hit, returns `{:ok, value}` and refreshes the key's access timestamp so it
  becomes most-recently-used. On a miss, returns `:miss`.
  """
  @spec get(server(), key()) :: {:ok, value()} | :miss
  def get(server, key) do
    GenServer.call(server, {:get, key})
  end

  @doc """
  Removes `key` from the cache. Returns `:ok` whether or not the key existed. A
  delete does not count as an access.
  """
  @spec delete(server(), key()) :: :ok
  def delete(server, key) do
    GenServer.call(server, {:delete, key})
  end

  @doc """
  Returns the current number of entries, a non-negative integer that never exceeds
  the configured capacity.
  """
  @spec size(server()) :: non_neg_integer()
  def size(server) do
    GenServer.call(server, :size)
  end

  @doc """
  Returns all keys ordered from most-recently-used to least-recently-used. Returns
  `[]` when the cache is empty.
  """
  @spec keys_by_recency(server()) :: [key()]
  def keys_by_recency(server) do
    GenServer.call(server, :keys_by_recency)
  end

  ## GenServer callbacks

  @impl true
  @spec init(map()) :: {:ok, map()}
  def init(%{capacity: capacity, clock: clock}) do
    {:ok, %{capacity: capacity, clock: clock, entries: %{}}}
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    ts = state.clock.()
    entries = state.entries

    entries =
      if Map.has_key?(entries, key) or map_size(entries) < state.capacity do
        entries
      else
        {oldest_key, _entry} = Enum.min_by(entries, fn {_k, entry} -> entry.access_ts end)
        Map.delete(entries, oldest_key)
      end

    entries = Map.put(entries, key, %{value: value, access_ts: ts})
    {:reply, :ok, %{state | entries: entries}}
  end

  def handle_call({:get, key}, _from, state) do
    case Map.fetch(state.entries, key) do
      {:ok, entry} ->
        ts = state.clock.()
        entries = Map.put(state.entries, key, %{entry | access_ts: ts})
        {:reply, {:ok, entry.value}, %{state | entries: entries}}

      :error ->
        {:reply, :miss, state}
    end
  end

  def handle_call({:delete, key}, _from, state) do
    {:reply, :ok, %{state | entries: Map.delete(state.entries, key)}}
  end

  def handle_call(:size, _from, state) do
    {:reply, map_size(state.entries), state}
  end

  def handle_call(:keys_by_recency, _from, state) do
    keys =
      state.entries
      |> Enum.sort_by(fn {_k, entry} -> entry.access_ts end, :desc)
      |> Enum.map(fn {k, _entry} -> k end)

    {:reply, keys, state}
  end
end