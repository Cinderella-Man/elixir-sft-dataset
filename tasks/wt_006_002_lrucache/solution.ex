defmodule LRUCache do
  @moduledoc """
  A GenServer-based cache with a fixed maximum number of entries and
  least-recently-used eviction.

  Each entry carries an access timestamp drawn from an injectable clock.
  On every `get/2` hit and every `put/3`, the entry's timestamp is refreshed
  to the current clock value; `put/3` that would overflow capacity evicts
  the entry with the smallest timestamp.

  No TTL, no periodic sweep: memory is bounded by `capacity` by construction.

  ## Options

    * `:name`      – optional process registration
    * `:capacity`  – required positive integer (max entries)
    * `:clock`     – `(-> integer())` returning a monotonically-increasing
                     value in any unit (default `&System.monotonic_time/0`)

  ## Examples

      iex> {:ok, pid} = LRUCache.start_link(capacity: 2)
      iex> LRUCache.put(pid, :a, 1)
      :ok
      iex> LRUCache.put(pid, :b, 2)
      :ok
      iex> LRUCache.put(pid, :c, 3)  # evicts :a
      :ok
      iex> LRUCache.get(pid, :a)
      :miss

  """

  use GenServer

  defstruct [:clock, :capacity, entries: %{}]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    capacity = Keyword.fetch!(opts, :capacity)

    unless is_integer(capacity) and capacity > 0 do
      raise ArgumentError, ":capacity must be a positive integer, got: #{inspect(capacity)}"
    end

    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @spec put(GenServer.server(), term(), term()) :: :ok
  def put(server, key, value), do: GenServer.call(server, {:put, key, value})

  @spec get(GenServer.server(), term()) :: {:ok, term()} | :miss
  def get(server, key), do: GenServer.call(server, {:get, key})

  @spec delete(GenServer.server(), term()) :: :ok
  def delete(server, key), do: GenServer.call(server, {:delete, key})

  @spec size(GenServer.server()) :: non_neg_integer()
  def size(server), do: GenServer.call(server, :size)

  @spec keys_by_recency(GenServer.server()) :: [term()]
  def keys_by_recency(server), do: GenServer.call(server, :keys_by_recency)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, &System.monotonic_time/0)
    capacity = Keyword.fetch!(opts, :capacity)

    {:ok, %__MODULE__{clock: clock, capacity: capacity}}
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    now = state.clock.()
    entry = %{value: value, access_ts: now}

    entries =
      cond do
        # Key already present — overwrite, no eviction, size unchanged.
        Map.has_key?(state.entries, key) ->
          Map.put(state.entries, key, entry)

        # New key, cache at capacity — evict LRU first.
        map_size(state.entries) >= state.capacity ->
          state.entries
          |> evict_lru()
          |> Map.put(key, entry)

        # New key, capacity available.
        true ->
          Map.put(state.entries, key, entry)
      end

    {:reply, :ok, %{state | entries: entries}}
  end

  def handle_call({:get, key}, _from, state) do
    case Map.fetch(state.entries, key) do
      {:ok, %{value: value} = entry} ->
        # Refresh access timestamp — LRU correctness requires this mutation.
        updated = %{entry | access_ts: state.clock.()}
        {:reply, {:ok, value}, %{state | entries: Map.put(state.entries, key, updated)}}

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
      |> Enum.sort_by(fn {_k, %{access_ts: ts}} -> ts end, :desc)
      |> Enum.map(fn {k, _} -> k end)

    {:reply, keys, state}
  end

  # ---------------------------------------------------------------------------
  # Eviction — O(n) scan for the smallest access_ts
  # ---------------------------------------------------------------------------

  defp evict_lru(entries) when map_size(entries) == 0, do: entries

  defp evict_lru(entries) do
    {lru_key, _} = Enum.min_by(entries, fn {_k, %{access_ts: ts}} -> ts end)
    Map.delete(entries, lru_key)
  end
end
