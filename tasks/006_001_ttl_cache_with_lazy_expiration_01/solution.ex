defmodule TTLCache do
  @moduledoc """
  A GenServer-based cache that stores key-value pairs with per-key TTL expiration.

  Expiration is enforced lazily on reads and periodically via a background sweep
  to prevent memory leaks from keys that are written but never read again.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Starts the cache process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc "Stores `value` under `key` with a TTL of `ttl_ms` milliseconds."
  @spec put(GenServer.server(), term(), term(), non_neg_integer()) :: :ok
  def put(server, key, value, ttl_ms) do
    GenServer.call(server, {:put, key, value, ttl_ms})
  end

  @doc "Retrieves the value for `key`, returning `{:ok, value}` or `:miss`."
  @spec get(GenServer.server(), term()) :: {:ok, term()} | :miss
  def get(server, key) do
    GenServer.call(server, {:get, key})
  end

  @doc "Deletes `key` from the cache. Always returns `:ok`."
  @spec delete(GenServer.server(), term()) :: :ok
  def delete(server, key) do
    GenServer.call(server, {:delete, key})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @default_sweep_interval_ms 60_000

  defstruct [:clock, :sweep_interval_ms, entries: %{}]

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    sweep_interval_ms = Keyword.get(opts, :sweep_interval_ms, @default_sweep_interval_ms)

    state = %__MODULE__{
      clock: clock,
      sweep_interval_ms: sweep_interval_ms
    }

    schedule_sweep(sweep_interval_ms)

    {:ok, state}
  end

  @impl true
  def handle_call({:put, key, value, ttl_ms}, _from, state) do
    expires_at = state.clock.() + ttl_ms
    entry = %{value: value, expires_at: expires_at}
    {:reply, :ok, %{state | entries: Map.put(state.entries, key, entry)}}
  end

  def handle_call({:get, key}, _from, state) do
    case Map.fetch(state.entries, key) do
      {:ok, %{value: value, expires_at: expires_at}} ->
        if state.clock.() < expires_at do
          {:reply, {:ok, value}, state}
        else
          {:reply, :miss, %{state | entries: Map.delete(state.entries, key)}}
        end

      :error ->
        {:reply, :miss, state}
    end
  end

  def handle_call({:delete, key}, _from, state) do
    {:reply, :ok, %{state | entries: Map.delete(state.entries, key)}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = state.clock.()

    pruned =
      state.entries
      |> Enum.reject(fn {_key, %{expires_at: expires_at}} -> now >= expires_at end)
      |> Map.new()

    schedule_sweep(state.sweep_interval_ms)

    {:noreply, %{state | entries: pruned}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp schedule_sweep(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :sweep, interval_ms)
  end

  defp schedule_sweep(_), do: :ok
end
