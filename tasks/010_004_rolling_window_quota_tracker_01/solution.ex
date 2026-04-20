defmodule QuotaTracker do
  @moduledoc """
  A GenServer that tracks per-key usage against configurable rolling-window quotas.

  Each key maintains a list of timestamped usage entries. Entries age out of
  the rolling window automatically, and usage is checked against a caller-supplied
  quota on each `record` call.

  ## Options

    * `:name`               - process registration name (optional)
    * `:max_window_ms`      - maximum retention for sweep (default: 3_600_000 / 1 hour)
    * `:cleanup_interval_ms`- how often the sweep runs in ms (default: 60_000 / 1 min)
    * `:clock`              - zero-arity fn returning current time in ms;
                              defaults to `fn -> System.monotonic_time(:millisecond) end`

  ## Examples

      {:ok, pid} = QuotaTracker.start_link()

      {:ok, 7} = QuotaTracker.record(pid, :api_calls, 3, 10, 60_000)
      {:ok, 2} = QuotaTracker.record(pid, :api_calls, 5, 10, 60_000)
      {:error, :quota_exceeded, 1} = QuotaTracker.record(pid, :api_calls, 3, 10, 60_000)

      {:ok, 2} = QuotaTracker.remaining(pid, :api_calls, 10, 60_000)
      {:ok, 8} = QuotaTracker.usage(pid, :api_calls, 60_000)
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type server :: GenServer.server()
  @type key :: term()

  @type usage_entry :: %{
          amount: non_neg_integer(),
          recorded_at: integer()
        }

  @type state :: %{
          entries: %{key() => [usage_entry()]},
          max_window_ms: non_neg_integer(),
          cleanup_interval_ms: non_neg_integer(),
          clock: (() -> integer())
        }

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_max_window_ms 3_600_000
  @default_cleanup_interval_ms 60_000
  @default_clock &__MODULE__.__default_clock__/0

  @doc false
  def __default_clock__, do: System.monotonic_time(:millisecond)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the `QuotaTracker` process.

  ## Options

    * `:name`                - passed directly to `GenServer.start_link/3`
    * `:max_window_ms`       - maximum retention for sweep (default #{@default_max_window_ms} ms)
    * `:cleanup_interval_ms` - sweep interval (default #{@default_cleanup_interval_ms} ms)
    * `:clock`               - zero-arity fn returning current time in ms
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name_opt, init_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {[], rest}
        {name, rest} -> {[name: name], rest}
      end

    GenServer.start_link(__MODULE__, init_opts, name_opt)
  end

  @doc """
  Records `amount` units of usage for `key` against `quota` within `window_ms`.

  Returns `{:ok, remaining}` on success, or `{:error, :quota_exceeded, overage}`
  if recording would push usage above the quota. Rejected recordings are not stored.
  """
  @spec record(server(), key(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, :quota_exceeded, non_neg_integer()}
  def record(server, key, amount, quota, window_ms) do
    GenServer.call(server, {:record, key, amount, quota, window_ms})
  end

  @doc """
  Returns `{:ok, remaining}` — the remaining quota for `key` within `window_ms`.

  Read-only: does not record any usage but evicts expired entries.
  """
  @spec remaining(server(), key(), non_neg_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer()}
  def remaining(server, key, quota, window_ms) do
    GenServer.call(server, {:remaining, key, quota, window_ms})
  end

  @doc """
  Returns `{:ok, total_used}` — the total usage for `key` within `window_ms`.
  """
  @spec usage(server(), key(), non_neg_integer()) :: {:ok, non_neg_integer()}
  def usage(server, key, window_ms) do
    GenServer.call(server, {:usage, key, window_ms})
  end

  @doc """
  Clears all usage history for `key`. Returns `:ok` always.
  """
  @spec reset(server(), key()) :: :ok
  def reset(server, key) do
    GenServer.call(server, {:reset, key})
  end

  @doc """
  Returns a list of all keys that have any recorded usage entries.
  """
  @spec keys(server()) :: [key()]
  def keys(server) do
    GenServer.call(server, :keys)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    max_window_ms = Keyword.get(opts, :max_window_ms, @default_max_window_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    clock = Keyword.get(opts, :clock, @default_clock)

    state = %{
      entries: %{},
      max_window_ms: max_window_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      clock: clock
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:record, key, amount, quota, window_ms}, _from, state) do
    now = state.clock.()
    current_entries = evict_expired(Map.get(state.entries, key, []), now, window_ms)
    current_usage = sum_usage(current_entries)

    if current_usage + amount > quota do
      overage = current_usage + amount - quota
      new_entries = Map.put(state.entries, key, current_entries)
      {:reply, {:error, :quota_exceeded, overage}, %{state | entries: new_entries}}
    else
      new_entry = %{amount: amount, recorded_at: now}
      updated = [new_entry | current_entries]
      new_entries = Map.put(state.entries, key, updated)
      remaining = quota - (current_usage + amount)
      {:reply, {:ok, remaining}, %{state | entries: new_entries}}
    end
  end

  def handle_call({:remaining, key, quota, window_ms}, _from, state) do
    now = state.clock.()
    current_entries = evict_expired(Map.get(state.entries, key, []), now, window_ms)
    current_usage = sum_usage(current_entries)

    new_entries =
      if current_entries == [] do
        Map.delete(state.entries, key)
      else
        Map.put(state.entries, key, current_entries)
      end

    remaining = max(quota - current_usage, 0)
    {:reply, {:ok, remaining}, %{state | entries: new_entries}}
  end

  def handle_call({:usage, key, window_ms}, _from, state) do
    now = state.clock.()
    current_entries = evict_expired(Map.get(state.entries, key, []), now, window_ms)
    total = sum_usage(current_entries)

    new_entries =
      if current_entries == [] do
        Map.delete(state.entries, key)
      else
        Map.put(state.entries, key, current_entries)
      end

    {:reply, {:ok, total}, %{state | entries: new_entries}}
  end

  def handle_call({:reset, key}, _from, state) do
    new_entries = Map.delete(state.entries, key)
    {:reply, :ok, %{state | entries: new_entries}}
  end

  def handle_call(:keys, _from, state) do
    {:reply, Map.keys(state.entries), state}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    now = state.clock.()

    surviving_entries =
      state.entries
      |> Enum.map(fn {key, entries} ->
        {key, evict_expired(entries, now, state.max_window_ms)}
      end)
      |> Enum.reject(fn {_key, entries} -> entries == [] end)
      |> Map.new()

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | entries: surviving_entries}}
  end

  def handle_info(msg, state) do
    require Logger
    Logger.warning("#{__MODULE__} received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end

  defp schedule_cleanup(_), do: :ok

  @spec evict_expired([usage_entry()], integer(), non_neg_integer()) :: [usage_entry()]
  defp evict_expired(entries, now, window_ms) do
    cutoff = now - window_ms

    Enum.filter(entries, fn entry ->
      entry.recorded_at > cutoff
    end)
  end

  @spec sum_usage([usage_entry()]) :: non_neg_integer()
  defp sum_usage(entries) do
    Enum.reduce(entries, 0, fn entry, acc -> acc + entry.amount end)
  end
end
