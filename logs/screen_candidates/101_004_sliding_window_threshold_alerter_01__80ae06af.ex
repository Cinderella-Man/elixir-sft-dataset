defmodule SlidingAlerter do
  @moduledoc """
  A GenServer that watches a sliding-window event rate per key and reports an
  alarm state when the rate crosses a configured threshold.

  Events are recorded per key into fixed-width sub-buckets of `:bucket_ms`
  milliseconds. The bucket index for an event at time `t` is `div(t, bucket_ms)`.
  When counting events for the alerting window, a bucket is included if and only
  if its start time (`index * bucket_ms`) is greater than or equal to
  `now - window_ms`.

  A key is in `:alarm` when its windowed count is greater than or equal to
  `:threshold`, and `:ok` otherwise. The alarm is self-clearing: as events slide
  out of the window the count falls, and once it drops below the threshold the
  status returns to `:ok` without any explicit reset.

  A periodic cleanup (scheduled with `Process.send_after/3`) drops buckets that
  start before `now - window_ms`, and removes keys entirely once they have no
  live buckets left, so memory does not grow without bound. Sending `:cleanup`
  directly to the process triggers the same sweep, which is handy in tests.

  ## Example

      {:ok, pid} = SlidingAlerter.start_link(threshold: 3, window_ms: 10_000)
      SlidingAlerter.record(pid, "user:a")
      #=> :ok
      SlidingAlerter.record(pid, "user:a")
      #=> :ok
      SlidingAlerter.record(pid, "user:a")
      #=> :alarm
  """

  use GenServer

  @type key :: term()
  @type status :: :ok | :alarm
  @type server :: GenServer.server()

  @default_bucket_ms 1_000
  @default_threshold 5
  @default_window_ms 60_000
  @default_cleanup_interval_ms 60_000

  # -- Public API ------------------------------------------------------------

  @doc """
  Starts the alerter process.

  ## Options

    * `:clock` — zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:bucket_ms` — width of each internal sub-bucket in milliseconds.
      Defaults to `#{@default_bucket_ms}`.
    * `:threshold` — count within the window at or above which a key is in alarm.
      Defaults to `#{@default_threshold}`.
    * `:window_ms` — sliding alerting window width in milliseconds.
      Defaults to `#{@default_window_ms}`.
    * `:cleanup_interval_ms` — how often to sweep expired buckets. Defaults to
      `#{@default_cleanup_interval_ms}`. Pass `:infinity` to disable.
    * `:name` — optional process registration name.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Records one event for `key` at the current clock time and returns the key's
  resulting status (`:ok` or `:alarm`).
  """
  @spec record(server(), key()) :: status()
  def record(server, key) do
    GenServer.call(server, {:record, key})
  end

  @doc """
  Returns the current status (`:ok` or `:alarm`) for `key` without recording
  an event. A key that has never been recorded is `:ok`.
  """
  @spec status(server(), key()) :: status()
  def status(server, key) do
    GenServer.call(server, {:status, key})
  end

  @doc """
  Returns the number of events recorded for `key` that fall within the last
  `:window_ms` milliseconds relative to the current clock time. A key that has
  never been recorded has a count of `0`.
  """
  @spec count(server(), key()) :: non_neg_integer()
  def count(server, key) do
    GenServer.call(server, {:count, key})
  end

  # -- GenServer callbacks ---------------------------------------------------

  @impl GenServer
  def init(opts) do
    state = %{
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      bucket_ms: Keyword.get(opts, :bucket_ms, @default_bucket_ms),
      threshold: Keyword.get(opts, :threshold, @default_threshold),
      window_ms: Keyword.get(opts, :window_ms, @default_window_ms),
      cleanup_interval_ms: Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms),
      keys: %{}
    }

    schedule_cleanup(state.cleanup_interval_ms)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:record, key}, _from, state) do
    now = state.clock.()
    bucket = div(now, state.bucket_ms)

    buckets =
      state.keys
      |> Map.get(key, %{})
      |> Map.update(bucket, 1, &(&1 + 1))

    state = %{state | keys: Map.put(state.keys, key, buckets)}
    {:reply, status_for(buckets, now, state), state}
  end

  def handle_call({:status, key}, _from, state) do
    now = state.clock.()
    buckets = Map.get(state.keys, key, %{})
    {:reply, status_for(buckets, now, state), state}
  end

  def handle_call({:count, key}, _from, state) do
    now = state.clock.()
    buckets = Map.get(state.keys, key, %{})
    {:reply, count_for(buckets, now, state), state}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    state = %{state | keys: prune(state.keys, state.clock.(), state)}
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # -- Internals -------------------------------------------------------------

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval) when is_integer(interval) and interval >= 0 do
    Process.send_after(self(), :cleanup, interval)
    :ok
  end

  defp status_for(buckets, now, state) do
    if count_for(buckets, now, state) >= state.threshold, do: :alarm, else: :ok
  end

  defp count_for(buckets, now, state) do
    cutoff = now - state.window_ms

    Enum.reduce(buckets, 0, fn {bucket, count}, acc ->
      if live?(bucket, cutoff, state.bucket_ms), do: acc + count, else: acc
    end)
  end

  defp prune(keys, now, state) do
    cutoff = now - state.window_ms

    Enum.reduce(keys, %{}, fn {key, buckets}, acc ->
      live = for {b, c} <- buckets, live?(b, cutoff, state.bucket_ms), into: %{}, do: {b, c}
      if map_size(live) == 0, do: acc, else: Map.put(acc, key, live)
    end)
  end

  defp live?(bucket, cutoff, bucket_ms), do: bucket * bucket_ms >= cutoff
end