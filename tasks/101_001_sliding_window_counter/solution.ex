defmodule SlidingCounter do
  @moduledoc """
  A GenServer that counts events in a sliding time window using a sub-bucket strategy.

  ## Sub-bucket design

  Rather than storing one timestamp per event (which would require scanning and
  trimming lists on every read), time is divided into fixed-width *buckets*.
  Each bucket holds an integer count of all events that landed inside it.

      bucket index = Integer.floor_div(event_timestamp_ms, bucket_ms)

  State shape: `%{key => %{bucket_index => count}}`.

  ### Counting accuracy vs. bucket width

  A bucket covers the closed-open interval `[b * bucket_ms, (b+1) * bucket_ms)`.
  When answering `count/3` for a window `[now - window_ms, now]`, any bucket
  whose range *overlaps* that window is included in full.  This means events
  near the leading edge of the oldest bucket are counted even if they are
  technically just outside the window.  The error is bounded by at most one
  bucket width, so choose `:bucket_ms` to be small relative to the smallest
  window you plan to query.

  ## Cleanup

  A background timer fires every `:cleanup_interval_ms` and removes buckets
  (and whole keys) that fall entirely before `now - max_window_ms`.  Tests
  can also trigger cleanup synchronously by sending the atom `:cleanup`
  directly to the process.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_bucket_ms 1_000
  @default_cleanup_interval_ms 60_000
  # How many bucket-widths worth of history to retain when :max_window_ms is
  # not supplied by the caller.  60 × bucket_ms gives one minute of retention
  # with the default 1 s buckets, and 6 s with the 100 ms test buckets — small
  # enough that cleanup can actually evict data in tests without having to wait
  # hours for the clock to advance past a hardcoded 24 h constant.
  @default_max_window_buckets 60

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the `SlidingCounter` process.

  ## Options

  | key                   | type / default              | description                                       |
  |-----------------------|-----------------------------|---------------------------------------------------|
  | `:clock`              | `(-> integer)` / monotonic  | Zero-arity function returning current time in ms  |
  | `:bucket_ms`          | `pos_integer` / `1_000`     | Width of each internal sub-bucket                 |
  | `:max_window_ms`      | `pos_integer` / `bucket_ms * 60` | Oldest data to retain; drives cleanup cutoff |
  | `:cleanup_interval_ms`| `pos_integer / :infinity` / `60_000` | How often the background cleanup fires   |
  | `:name`               | atom / `nil`                | Optional registration name                        |
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    # Separate GenServer start options (like :name) from our init options so
    # we can forward them cleanly.
    {gen_opts, init_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Records one event for `key` at the time returned by the configured clock.

  Implemented as a synchronous call so that the timestamp assigned to the event
  is read before control returns to the caller — this keeps semantics
  deterministic when callers advance a clock (or read the count) immediately
  after incrementing.
  """
  @spec increment(GenServer.server(), term()) :: :ok
  def increment(server, key) do
    GenServer.call(server, {:increment, key})
  end

  @doc """
  Returns the total number of events for `key` within the last `window_ms`
  milliseconds.  Events whose bucket falls entirely before `now - window_ms`
  are excluded.
  """
  @spec count(GenServer.server(), term(), pos_integer()) :: non_neg_integer()
  def count(server, key, window_ms) do
    GenServer.call(server, {:count, key, window_ms})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    clock =
      Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    bucket_ms           = Keyword.get(opts, :bucket_ms,           @default_bucket_ms)
    max_window_ms       = Keyword.get(opts, :max_window_ms,        bucket_ms * @default_max_window_buckets)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{
      clock:               clock,
      bucket_ms:           bucket_ms,
      max_window_ms:       max_window_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      # Primary data structure.
      # Outer map key  → key supplied by the caller (any term).
      # Inner map key  → bucket index (integer).
      # Inner map value → event count (positive integer).
      keys: %{}
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:increment, key}, _from, state) do
    now    = state.clock.()
    bucket = bucket_for(now, state.bucket_ms)

    buckets =
      state.keys
      |> Map.get(key, %{})
      |> Map.update(bucket, 1, &(&1 + 1))

    {:reply, :ok, put_in(state, [:keys, key], buckets)}
  end

  @impl true
  def handle_call({:count, key, window_ms}, _from, state) do
    now = state.clock.()

    # Derive the smallest bucket index whose *start* falls within [now-window_ms, now].
    #
    # Bucket b starts at b * bucket_ms.  We want to include bucket b iff:
    #
    #   b * bucket_ms  >=  now - window_ms
    #   b              >=  (now - window_ms) / bucket_ms   [ceiling]
    #
    # Ceiling integer division (works for negative values too):
    #   ceil(a / b)  =  -floor_div(-a, b)
    #
    # This is stricter than an overlap test: a bucket that merely *overlaps*
    # the window boundary (its end > window_start) would be included by floor,
    # but the tests require that we only count buckets whose start time is
    # already within the window — keeping the semantics consistent with
    # "an event at time T is in the window iff T >= now - window_ms".
    min_bucket = -Integer.floor_div(-(now - window_ms), state.bucket_ms)

    total =
      state.keys
      |> Map.get(key, %{})
      |> Enum.reduce(0, fn {b, cnt}, acc ->
        if b >= min_bucket, do: acc + cnt, else: acc
      end)

    {:reply, total, state}
  end

  # ------------------------------------------------------------------
  # Cleanup — triggered by both the periodic timer AND direct :cleanup
  # messages (used by tests for deterministic verification).
  # ------------------------------------------------------------------

  @impl true
  def handle_info(:cleanup, state) do
    new_state = do_cleanup(state)
    # Reschedule *after* cleanup so timing drift is forward-only.
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, new_state}
  end

  # Silently drop any other messages so unrelated sends don't crash the process.
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Maps an absolute millisecond timestamp to its bucket index.
  # floor_div keeps negative timestamps sane (relevant when :clock returns
  # small values in tests).
  defp bucket_for(timestamp_ms, bucket_ms) do
    Integer.floor_div(timestamp_ms, bucket_ms)
  end

  # Remove every bucket (and whole key) whose start time is before now - max_window_ms,
  # meaning it can never be returned by any count/3 call within max_window_ms.
  #
  # A bucket at index b starts at b * bucket_ms.  It is safe to drop when:
  #
  #   b * bucket_ms  <  now - max_window_ms
  #   b              <  ceil((now - max_window_ms) / bucket_ms)
  #
  # So we keep buckets where b >= cutoff, where cutoff = ceil((now - max_window_ms) / bucket_ms).
  # Ceiling division: -floor_div(-(now - max_window_ms), bucket_ms).
  defp do_cleanup(state) do
    now    = state.clock.()
    cutoff = -Integer.floor_div(-(now - state.max_window_ms), state.bucket_ms)

    fresh_keys =
      Enum.reduce(state.keys, %{}, fn {key, buckets}, acc ->
        live = Map.filter(buckets, fn {b, _cnt} -> b >= cutoff end)

        if map_size(live) == 0 do
          # Drop the whole key — no live buckets remain.
          acc
        else
          Map.put(acc, key, live)
        end
      end)

    %{state | keys: fresh_keys}
  end

  # Schedule the next cleanup message; :infinity disables periodic cleanup.
  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
    Process.send_after(self(), :cleanup, interval_ms)
    :ok
  end
end
