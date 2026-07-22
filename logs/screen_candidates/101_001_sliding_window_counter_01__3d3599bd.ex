defmodule SlidingCounter do
  @moduledoc """
  A `GenServer` that counts events per key inside a sliding time window using a
  fixed-width **sub-bucket** strategy.

  ## Sub-bucket design

  Time is divided into fixed-width sub-buckets of `:bucket_ms` milliseconds. An
  event recorded at time `t` is placed into the bucket whose index is the *floor*
  division of `t` by `bucket_ms`:

      b = floor(t / bucket_ms)

  Floor (rather than truncation towards zero) is used so that negative clock
  readings — which a monotonic clock may legitimately produce — behave exactly the
  same as positive ones. Bucket `b` therefore covers the half-open interval
  `[b * bucket_ms, (b + 1) * bucket_ms)`.

  Each bucket stores only an integer count, never individual timestamps, so many
  increments landing in the same bucket simply add to that bucket's counter. The
  memory used by a key is bounded by the number of *distinct* buckets it has seen
  inside the retention horizon, not by the number of events.

  ## Counting rule and the accuracy trade-off

  For `count/3` with `now` the current clock reading and
  `window_start = now - window_ms`, a bucket is included in the total **iff its
  start time is at or after `window_start`**:

      b * bucket_ms >= now - window_ms

  equivalently `b >= ceil((now - window_ms) / bucket_ms)`. Included buckets
  contribute their count *in full*; buckets starting before `window_start`
  contribute nothing at all, even when their range overlaps the leading edge of
  the window. A bucket whose start time is exactly `now - window_ms` **is**
  included — the boundary is inclusive on the old side.

  The practical consequence is that the effective cutoff is quantized to bucket
  boundaries, so a count can *under*-report the events sitting in the
  partially-overlapping oldest bucket. The error is bounded by one bucket width
  (`:bucket_ms`). Choose `:bucket_ms` small relative to the smallest window you
  intend to query: with a 1 second bucket and a 60 second window the worst-case
  error is under 2%, whereas querying a 2 second window with 1 second buckets can
  discard up to half of the events you might have expected.

  Counting is always relative to `now`, evaluated on every call, so the same key
  queried with the same `window_ms` may return a smaller number later purely
  because the clock moved. `count/3` is read-only: it never mutates state, never
  creates an entry for an unknown key, and returns `0` for keys that were never
  incremented or whose buckets have all aged out.

  ## Cleanup contract

  Memory must not leak, so the server periodically prunes old buckets:

    * The first cleanup is scheduled during `init/1` with `Process.send_after/3`,
      which sends the bare atom `:cleanup` to the process every
      `:cleanup_interval_ms`. When `:cleanup_interval_ms` is `:infinity`, no timer
      is ever armed.
    * `:cleanup` is handled in `handle_info/2` regardless of its origin, so it can
      be sent directly to force a cleanup on demand. After each pass the timer is
      re-armed exactly once (never when the interval is `:infinity`), so a
      directly-sent `:cleanup` is idempotent with respect to the timer and never
      spawns a second timer chain.
    * A pass reads the clock and drops every bucket whose start time is before
      `now - max_window_ms`, keeping bucket `b` iff
      `b >= ceil((now - max_window_ms) / bucket_ms)` — the same ceiling rule used
      by `count/3`. Cleanup therefore can never delete data that a `count/3` call
      with `window_ms <= max_window_ms` would still have counted.
    * A key with no surviving buckets is removed entirely, so no empty inner maps
      are left behind. If every key expires, `state.keys` becomes `%{}`.
    * Cleanup with a clock that has not advanced past the horizon is a no-op, and
      running it twice in a row changes nothing the second time.

  Any `handle_info/2` message other than `:cleanup` is silently ignored.

  ## State shape

  Counters live in `state.keys` as a map of `key => %{bucket_index => count}`, and
  it is exactly `%{}` when no data is live.

  ## Example

      {:ok, pid} = SlidingCounter.start_link(bucket_ms: 1_000)
      :ok = SlidingCounter.increment(pid, "page:home")
      1 = SlidingCounter.count(pid, "page:home", 60_000)
      0 = SlidingCounter.count(pid, "page:about", 60_000)

  """

  use GenServer

  @type key :: term()
  @type clock :: (-> integer())
  @type bucket_index :: integer()
  @type buckets :: %{optional(bucket_index()) => non_neg_integer()}
  @type server :: GenServer.server()

  @type option ::
          {:clock, clock()}
          | {:bucket_ms, pos_integer()}
          | {:max_window_ms, non_neg_integer()}
          | {:cleanup_interval_ms, pos_integer() | :infinity}
          | {:name, GenServer.name()}

  @type t :: %__MODULE__{
          clock: clock(),
          bucket_ms: pos_integer(),
          max_window_ms: non_neg_integer(),
          cleanup_interval_ms: pos_integer() | :infinity,
          keys: %{optional(key()) => buckets()}
        }

  defstruct clock: nil,
            bucket_ms: 1_000,
            max_window_ms: 60_000,
            cleanup_interval_ms: 60_000,
            keys: %{}

  @default_bucket_ms 1_000
  @default_cleanup_interval_ms 60_000
  @default_window_buckets 60

  # Public API

  @doc """
  Starts the sliding counter process.

  `opts` is an optional keyword list:

    * `:clock` — zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`. It is called
      afresh for every increment, count and cleanup; a reading is never cached.
      It may return negative integers.
    * `:bucket_ms` — width of each internal sub-bucket, in milliseconds.
      Defaults to `1_000`.
    * `:max_window_ms` — retention horizon used by cleanup; the oldest data the
      process promises to keep. Defaults to `bucket_ms * 60`.
    * `:cleanup_interval_ms` — how often the periodic cleanup runs. Defaults to
      `60_000`. Pass `:infinity` to disable the periodic timer entirely.
    * `:name` — optional registration name, forwarded to `GenServer.start_link/3`
      as a start option rather than treated as counter configuration.

  Returns whatever `GenServer.start_link/3` returns.
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {start_opts, config} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, config, start_opts)
  end

  @doc """
  Records one event for `key` at the current clock time.

  The event is added to the bucket covering the current time. `key` may be any
  term (binary, atom, tuple, …) and keys are compared by value.

  This is a synchronous call: once it returns, the event is already recorded and
  stamped, so the caller may advance a test clock or call `count/3` immediately
  afterwards and observe the event. Always returns `:ok`.
  """
  @spec increment(server(), key()) :: :ok
  def increment(server, key) do
    GenServer.call(server, {:increment, key})
  end

  @doc """
  Returns the number of events recorded for `key` within the last `window_ms`
  milliseconds, relative to the current clock reading.

  Buckets are included in full when their start time is at or after
  `now - window_ms`, and excluded entirely otherwise (see the module
  documentation for the accuracy trade-off this implies). Returns a plain
  non-negative integer — `0` for an unknown key or a key whose buckets have all
  aged out — and never mutates the server's state.
  """
  @spec count(server(), key(), non_neg_integer()) :: non_neg_integer()
  def count(server, key, window_ms) when is_integer(window_ms) and window_ms >= 0 do
    GenServer.call(server, {:count, key, window_ms})
  end

  # GenServer callbacks

  @impl GenServer
  @spec init(keyword()) :: {:ok, t()}
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    bucket_ms = Keyword.get(opts, :bucket_ms, @default_bucket_ms)
    max_window_ms = Keyword.get(opts, :max_window_ms, bucket_ms * @default_window_buckets)

    cleanup_interval_ms =
      Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %__MODULE__{
      clock: clock,
      bucket_ms: bucket_ms,
      max_window_ms: max_window_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      keys: %{}
    }

    schedule_cleanup(state)

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:increment, key}, _from, %__MODULE__{} = state) do
    now = state.clock.()
    index = bucket_index(now, state.bucket_ms)

    keys =
      Map.update(state.keys, key, %{index => 1}, fn buckets ->
        Map.update(buckets, index, 1, &(&1 + 1))
      end)

    {:reply, :ok, %{state | keys: keys}}
  end

  def handle_call({:count, key, window_ms}, _from, %__MODULE__{} = state) do
    now = state.clock.()
    cutoff = oldest_live_bucket(now, window_ms, state.bucket_ms)

    total =
      state.keys
      |> Map.get(key, %{})
      |> Enum.reduce(0, fn {index, count}, acc ->
        if index >= cutoff, do: acc + count, else: acc
      end)

    {:reply, total, state}
  end

  @impl GenServer
  def handle_info(:cleanup, %__MODULE__{} = state) do
    state = prune(state)
    schedule_cleanup(state)
    {:noreply, state}
  end

  def handle_info(_message, %__MODULE__{} = state) do
    {:noreply, state}
  end

  # Internal helpers

  @spec prune(t()) :: t()
  defp prune(%__MODULE__{} = state) do
    now = state.clock.()
    cutoff = oldest_live_bucket(now, state.max_window_ms, state.bucket_ms)

    keys =
      Enum.reduce(state.keys, %{}, fn {key, buckets}, acc ->
        live = for {index, count} <- buckets, index >= cutoff, into: %{}, do: {index, count}

        if map_size(live) == 0, do: acc, else: Map.put(acc, key, live)
      end)

    %{state | keys: keys}
  end

  @spec schedule_cleanup(t()) :: :ok
  defp schedule_cleanup(%__MODULE__{cleanup_interval_ms: :infinity}), do: :ok

  defp schedule_cleanup(%__MODULE__{cleanup_interval_ms: interval}) do
    Process.send_after(self(), :cleanup, interval)
    :ok
  end

  # Index of the bucket containing `time`, using floor division so that negative
  # clock readings bucket consistently with positive ones.
  @spec bucket_index(integer(), pos_integer()) :: bucket_index()
  defp bucket_index(time, bucket_ms), do: Integer.floor_div(time, bucket_ms)

  # Index of the oldest bucket whose start time is at or after `now - span_ms`,
  # i.e. `ceil((now - span_ms) / bucket_ms)`, expressed with floor division so it
  # stays exact for negative values.
  @spec oldest_live_bucket(integer(), non_neg_integer(), pos_integer()) :: bucket_index()
  defp oldest_live_bucket(now, span_ms, bucket_ms) do
    -Integer.floor_div(-(now - span_ms), bucket_ms)
  end
end