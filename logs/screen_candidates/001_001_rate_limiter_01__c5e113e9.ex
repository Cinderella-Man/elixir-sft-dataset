defmodule RateLimiter do
  @moduledoc """
  A `GenServer` that enforces per-key rate limits using a sliding-window algorithm.

  Each key is tracked independently: limiting `"user:1"` has no effect on `"user:2"`.
  For every key the server keeps the timestamps of the requests that fall inside the
  most recently used window. A request is admitted when fewer than `max_requests`
  timestamps remain inside the `(now - window_ms, now]` interval.

  To avoid unbounded memory growth, a periodic cleanup pass (scheduled with
  `Process.send_after/3`) discards tracking data for windows that have fully expired.
  The interval is configurable via the `:cleanup_interval_ms` option and may be
  `:infinity` to disable automatic cleanup entirely. Sending the process a bare
  `:cleanup` message performs a single cleanup pass on demand.

  The current time source is injectable through the `:clock` option, which must be a
  zero-arity function returning milliseconds. This makes the sliding-window behaviour
  fully deterministic under test.
  """

  use GenServer

  @default_cleanup_interval_ms 60_000

  @typedoc "A zero-arity function returning the current time in milliseconds."
  @type clock :: (-> integer())

  @typedoc "Per-key tracking data: the retained timestamps and the last window size."
  @type entry :: %{times: [integer()], window_ms: non_neg_integer()}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the rate limiter process.

  ## Options

    * `:clock` - a zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:name` - an optional name for process registration.
    * `:cleanup_interval_ms` - how often, in milliseconds, to run the cleanup pass.
      May be `:infinity` to disable automatic cleanup. Defaults to `60_000`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, init_opts)
      name -> GenServer.start_link(__MODULE__, init_opts, name: name)
    end
  end

  @doc """
  Checks whether a request for `key` is allowed under the given limit.

  At most `max_requests` requests are permitted within any sliding window of
  `window_ms` milliseconds. When the request is admitted, returns `{:ok, remaining}`
  where `remaining` is the number of further requests still available in the current
  window. When the request is rejected, returns `{:error, :rate_limited, retry_after_ms}`
  where `retry_after_ms` is how long the caller should wait before the oldest tracked
  request leaves the window.
  """
  @spec check(GenServer.server(), term(), non_neg_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, :rate_limited, non_neg_integer()}
  def check(server, key, max_requests, window_ms)
      when is_integer(max_requests) and max_requests >= 0 and
             is_integer(window_ms) and window_ms >= 0 do
    GenServer.call(server, {:check, key, max_requests, window_ms})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    interval = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{clock: clock, cleanup_interval_ms: interval, table: %{}}
    schedule_cleanup(interval)
    {:ok, state}
  end

  @impl true
  def handle_call({:check, key, max_requests, window_ms}, _from, state) do
    now = state.clock.()
    cutoff = now - window_ms

    %{times: times} = Map.get(state.table, key, %{times: [], window_ms: window_ms})
    recent = Enum.filter(times, fn ts -> ts > cutoff end)
    count = length(recent)

    if count < max_requests do
      entry = %{times: [now | recent], window_ms: window_ms}
      new_table = Map.put(state.table, key, entry)
      remaining = max_requests - count - 1
      {:reply, {:ok, remaining}, %{state | table: new_table}}
    else
      entry = %{times: recent, window_ms: window_ms}
      new_table = Map.put(state.table, key, entry)
      retry_after_ms = Enum.min(recent) + window_ms - now
      {:reply, {:error, :rate_limited, retry_after_ms}, %{state | table: new_table}}
    end
  end

  @impl true
  def handle_info(:__cleanup_tick__, state) do
    new_state = purge_expired(state)
    schedule_cleanup(new_state.cleanup_interval_ms)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    {:noreply, purge_expired(state)}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  @spec schedule_cleanup(non_neg_integer() | :infinity) :: :ok
  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval) when is_integer(interval) do
    Process.send_after(self(), :__cleanup_tick__, interval)
    :ok
  end

  @spec purge_expired(map()) :: map()
  defp purge_expired(state) do
    now = state.clock.()

    new_table =
      Enum.reduce(state.table, %{}, fn {key, %{times: times, window_ms: window_ms}}, acc ->
        recent = Enum.filter(times, fn ts -> ts > now - window_ms end)

        case recent do
          [] -> acc
          _ -> Map.put(acc, key, %{times: recent, window_ms: window_ms})
        end
      end)

    %{state | table: new_table}
  end
end