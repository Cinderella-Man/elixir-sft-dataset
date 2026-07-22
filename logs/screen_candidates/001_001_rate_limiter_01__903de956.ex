defmodule RateLimiter do
  @moduledoc """
  A `GenServer` that enforces per-key rate limits using a sliding window algorithm.

  Each key is tracked independently: the server keeps the list of timestamps at which
  requests for that key were allowed, together with the `window_ms` most recently used
  for the key. A timestamp is *active* at time `now` when `ts > now - window_ms`, so an
  entry recorded exactly `window_ms` milliseconds ago has already fallen out of the
  window.

  A request is allowed when the number of active timestamps is below `max_requests`.
  Allowed requests record `now`; denied requests record nothing, so hammering a limited
  key never pushes its window forward.

  To avoid unbounded memory growth, a periodic `:cleanup` pass (every
  `:cleanup_interval_ms`, default `60_000`) prunes expired timestamps and drops keys
  whose active list becomes empty. Cleanup is purely a memory reclamation pass: it never
  changes the outcome of a subsequent `check/4`.

  ## Options

    * `:clock` - zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`. It is called afresh
      whenever the server needs "now".
    * `:cleanup_interval_ms` - interval between cleanup passes, in milliseconds, or
      `:infinity` to disable the automatic sweep. Defaults to `60_000`.
    * `:name` - optional name used for process registration.

  ## Example

      {:ok, pid} = RateLimiter.start_link(name: MyLimiter)
      {:ok, 4} = RateLimiter.check(MyLimiter, "user:1", 5, 1_000)

  """

  use GenServer

  @default_cleanup_interval_ms 60_000

  @typedoc "A zero-arity function returning the current time in milliseconds."
  @type clock :: (-> integer())

  @typedoc "Any term may be used as a rate limiting key; keys are compared by value."
  @type key :: term()

  @typedoc "Result of a `check/4` call."
  @type check_result :: {:ok, non_neg_integer()} | {:error, :rate_limited, pos_integer()}

  # Internal state.
  #
  #   * `:clock` - the configured clock function
  #   * `:cleanup_interval_ms` - integer interval or `:infinity`
  #   * `:entries` - `%{key => {window_ms, [timestamp]}}`, timestamps newest-first
  defstruct clock: nil, cleanup_interval_ms: @default_cleanup_interval_ms, entries: %{}

  ## Public API

  @doc """
  Starts the rate limiter and links it to the calling process.

  Accepts the `:clock`, `:cleanup_interval_ms` and `:name` options described in the
  module documentation. When `:name` is absent the process is started unregistered.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, server_opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, server_opts)
      name -> GenServer.start_link(__MODULE__, server_opts, name: name)
    end
  end

  @doc """
  Checks whether a request for `key` is allowed under a limit of `max_requests` per
  `window_ms` milliseconds.

  Returns `{:ok, remaining}` when the request is allowed, where `remaining` is the number
  of further requests available in the current window (`0` on the last allowed call).

  Returns `{:error, :rate_limited, retry_after_ms}` when the request is denied.
  `retry_after_ms` is at least `1` and is the delay after which the oldest tracked request
  drops out of the window, freeing a slot.

  `max_requests` and `window_ms` are supplied per call, so the same key may be checked
  against different limits over time.
  """
  @spec check(GenServer.server(), key(), pos_integer(), pos_integer()) :: check_result()
  def check(server, key, max_requests, window_ms)
      when is_integer(max_requests) and max_requests > 0 and
             is_integer(window_ms) and window_ms > 0 do
    GenServer.call(server, {:check, key, max_requests, window_ms})
  end

  ## GenServer callbacks

  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      cleanup_interval_ms:
        Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms),
      entries: %{}
    }

    schedule_cleanup(state.cleanup_interval_ms)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:check, key, max_requests, window_ms}, _from, state) do
    now = state.clock.()
    active = key |> current_timestamps(state) |> prune(now, window_ms)
    count = length(active)

    if count < max_requests do
      entries = Map.put(state.entries, key, {window_ms, [now | active]})
      {:reply, {:ok, max_requests - count - 1}, %{state | entries: entries}}
    else
      entries = Map.put(state.entries, key, {window_ms, active})
      oldest = List.last(active)
      retry_after_ms = max(oldest + window_ms - now, 1)
      {:reply, {:error, :rate_limited, retry_after_ms}, %{state | entries: entries}}
    end
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    now = state.clock.()

    entries =
      Enum.reduce(state.entries, %{}, fn {key, {window_ms, timestamps}}, acc ->
        case prune(timestamps, now, window_ms) do
          [] -> acc
          active -> Map.put(acc, key, {window_ms, active})
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | entries: entries}}
  end

  @impl GenServer
  def handle_info(_message, state), do: {:noreply, state}

  ## Internal helpers

  defp current_timestamps(key, state) do
    case Map.fetch(state.entries, key) do
      {:ok, {_window_ms, timestamps}} -> timestamps
      :error -> []
    end
  end

  # Timestamps are kept newest-first, so the active ones form a prefix of the list.
  defp prune(timestamps, now, window_ms) do
    cutoff = now - window_ms
    Enum.filter(timestamps, &(&1 > cutoff))
  end

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
    :ok
  end
end