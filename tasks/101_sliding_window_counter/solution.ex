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
  # Retain data for up to 24 h by default.  Callers that use shorter windows
  # should pass a tighter :max_window_ms so cleanup actually frees memory.
  @default_max_window_ms 86_400_000

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
  | `:max_window_ms`      | `pos_integer` / `86_400_000`| Oldest data to retain; drives cleanup cutoff      |
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

  This is a cast (fire-and-forget) so it never blocks the caller.
  """
  @spec increment(GenServer.server(), term()) :: :ok
  def increment(server, key) do
    GenServer.cast(server, {:increment, key})
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

    bucket_ms          = Keyword.get(opts, :bucket_ms,           @default_bucket_ms)
    max_window_ms      = Keyword.get(opts, :max_window_ms,        @default_max_window_ms)
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

  # ------------------------------------------------------------------
  # increment  (cast → non-blocking)
  # ------------------------------------------------------------------

  @impl true
  def handle_cast({:increment, key}, state) do
    now    = state.clock.()
    bucket = bucket_for(now, state.bucket_ms)

    # Fetch the bucket map for this key (default empty), bump the count,
    # then put it back.
    buckets =
      state.keys
      |> Map.get(key, %{})
      |> Map.update(bucket, 1, &(&1 + 1))

    {:noreply, put_in(state, [:keys, key], buckets)}
  end

  # ------------------------------------------------------------------
  # count  (call → synchronous reply)
  # ------------------------------------------------------------------

  @impl true
  def handle_call({:count, key, window_ms}, _from, state) do
    now = state.clock.()

    # Derive the smallest bucket index whose range overlaps [now-window_ms, now].
    #
    # Bucket b covers the half-open interval [b*bms, (b+1)*bms).
    # Overlap with the window requires:
    #   (b+1)*bms  > now - window_ms
    #   b+1        > (now - window_ms) / bms
    #   b          >= ceil((now - window_ms) / bms)
    #              =  floor_div(now - window_ms, bms)
    #                 when (now - window_ms) is exactly divisible (b+1 would equal
    #                 the boundary, meaning bucket b ends *at* window start and
    #                 therefore does NOT overlap — handled correctly because
    #                 floor_div(n*bms, bms) == n, so b >= n means bucket n is the
    #                 first included one).
    #
    # Using Integer.floor_div/2 rather than div/2 ensures correctness when
    # (now - window_ms) is negative (e.g., early in a monotonic clock epoch).
    min_bucket = Integer.floor_div(now - window_ms, state.bucket_ms)

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

  # Remove every bucket (and whole key) that can no longer fall inside any
  # window of size <= max_window_ms anchored at the current time.
  #
  # A bucket at index b is fully expired when its entire range lies before
  # the oldest possible window start:
  #
  #   (b+1) * bucket_ms  <=  now - max_window_ms
  #   b                  <   floor_div(now - max_window_ms, bucket_ms)
  #
  # Equivalently we keep buckets where b >= cutoff.
  defp do_cleanup(state) do
    now    = state.clock.()
    cutoff = Integer.floor_div(now - state.max_window_ms, state.bucket_ms)

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
