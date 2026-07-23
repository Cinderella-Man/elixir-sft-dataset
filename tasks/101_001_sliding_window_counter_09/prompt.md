# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `handle_info` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

**Summary:** Implement `SlidingCounter`, an Elixir GenServer that counts events in a sliding time window via fixed-width sub-buckets. Single file, OTP standard library only, no external dependencies.

**Public API — `SlidingCounter.start_link(opts)`**
- Starts the process. `opts` is a keyword list and must be optional (default `[]`).
- Returns whatever `GenServer.on_start()` normally returns (`{:ok, pid}`, `{:error, {:already_started, pid}}`, …).
- `:clock` — zero-arity function returning current time in milliseconds. Default `fn -> System.monotonic_time(:millisecond) end`.
- `:clock` — every timestamp the server uses (increments, counts, cleanup) must come from calling this function at the moment it is needed, never from a cached value.
- `:clock` — may return negative integers (a monotonic clock legitimately can); every rule below must still hold for negative times.
- `:bucket_ms` — width of each internal sub-bucket in milliseconds. Default `1_000` (1 second).
- `:max_window_ms` — retention horizon used by cleanup: the oldest data the process promises to keep. Default `bucket_ms * 60` (one minute at the default bucket width; scales down automatically when a caller configures small buckets).
- `:cleanup_interval_ms` — how often the periodic cleanup runs. Default `60_000`. Pass `:infinity` to disable the periodic timer entirely.
- `:name` — optional process registration name. Must be forwarded to `GenServer.start_link/3` as a start option, not treated as counter config.

**Public API — `SlidingCounter.increment(server, key)`**
- Records one event for `key` at the current clock time. Returns `:ok`.
- `key` may be any term (binary, atom, tuple, …); keys are compared by value.
- Must be a **synchronous** call: when it returns, the event is already recorded and stamped, so a caller may advance its test clock or call `count/3` on the very next line and see the event.

**Public API — `SlidingCounter.count(server, key, window_ms)`**
- Returns a plain non-negative integer, not an `{:ok, _}` tuple: the total number of events recorded for `key` falling within the last `window_ms` milliseconds relative to the current clock time.
- Events outside that window must not be counted.
- Also a synchronous call.

**Bucketing**
- Divide time into fixed-width sub-buckets of `:bucket_ms` each.
- Each event goes into the bucket whose index is the *floor* division of its timestamp by `bucket_ms` — floor, not truncation; this is what keeps negative clock values sane.
- Bucket `b` covers the half-open interval `[b * bucket_ms, (b + 1) * bucket_ms)`.
- A bucket stores only an integer count, not individual timestamps; repeated increments landing in the same bucket simply add to that bucket's counter.

**Counting rule (exact, at the boundary)**
- For `count(server, key, window_ms)`: let `now` be the current clock reading and `window_start = now - window_ms`.
- A bucket is included **iff its start time is at or after `window_start`** — i.e. `b * bucket_ms >= now - window_ms`, equivalently `b >= ceil((now - window_ms) / bucket_ms)`.
- Included buckets contribute their count *in full*.
- Buckets that start before `window_start` contribute nothing at all, even if their range overlaps the window's leading edge.

**Guarantees callers may rely on**
- An event recorded at time `t` is counted iff its whole bucket starts inside the window, so the effective cutoff is quantized to bucket boundaries. The count can therefore *under*-report events sitting in the partially-overlapping oldest bucket; the error is bounded by one bucket width.
- Document that trade-off in the `@moduledoc` and tell users to pick `:bucket_ms` small relative to the smallest window they query.
- A bucket whose start time is exactly `now - window_ms` **is** included — the boundary is inclusive on the old side.
- The window is relative to `now` on every call: the same key with the same `window_ms` may return a smaller number later, purely because the clock moved.

**Unknown / empty cases**
- `count/3` returns `0` for a key that has never been incremented, and for a key whose buckets have all aged out or been cleaned up.
- It must not raise and must not create an entry for that key.
- Counting is read-only: it never mutates state, and repeated calls with an unchanged clock return the same number.

**Key isolation**
- Different keys are tracked independently: incrementing `"page:home"` must not affect `"page:about"`.
- Cleanup of one key must not disturb another.

**State shape**
- Keep counters in `state.keys` as a map of `key => %{bucket_index => count}`.
- Callers and cleanup assertions rely on `state.keys` being exactly that, and an empty map `%{}` when no data is live.

**Cleanup — memory must not leak**
- Schedule cleanup with `Process.send_after/3` sending the bare atom `:cleanup` to the process, every `:cleanup_interval_ms`. Schedule the first one during `init/1`. When `:cleanup_interval_ms` is `:infinity`, schedule nothing.
- Handle a `:cleanup` message in `handle_info/2` regardless of where it came from, so it can be sent directly to the process to force cleanup on demand.
- After handling it, re-arm the timer — again, no re-arming when the interval is `:infinity` — so a directly-sent `:cleanup` is idempotent with respect to the timer and never spawns a second timer chain.
- A cleanup pass reads the clock and drops every bucket whose start time is before `now - max_window_ms`: keep bucket `b` iff `b >= ceil((now - max_window_ms) / bucket_ms)`, the same ceiling rule used by `count/3`.
- That rule guarantees cleanup can never delete data a `count/3` call with `window_ms <= max_window_ms` would still have counted.
- When a key has no surviving buckets, remove the key from `state.keys` entirely — don't leave an empty inner map behind. If every key expires, `state.keys` becomes `%{}`.
- Cleanup with a clock that hasn't advanced past the horizon is a no-op: nothing is dropped and the state is unchanged. Running cleanup twice in a row changes nothing the second time.

**Other messages**
- Any `handle_info/2` message other than `:cleanup` is silently ignored (`{:noreply, state}`).
- A stray `send/2` from unrelated code must never crash the counter or alter its state.

**Deliverable**
- Complete module in a single file, with typespecs.
- `@moduledoc` explaining the sub-bucket design, the accuracy/bucket-width trade-off, and the cleanup contract.

## The module with `handle_info` missing

```elixir
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
  When answering `count/3` for a window `[now - window_ms, now]`, a bucket is
  included only when its start lies inside the window (a bucket starting exactly
  at `now - window_ms` counts).  The effective cutoff is therefore quantized to
  bucket boundaries, and events sitting in the partially-overlapping oldest
  bucket are *under*-reported.  The error is bounded by at most one bucket
  width, so choose `:bucket_ms` to be small relative to the smallest window you
  plan to query.

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

  | key                    | type / default                   | description                    |
  |------------------------|----------------------------------|--------------------------------|
  | `:clock`               | `(-> integer)` / monotonic       | Current time in ms (0-arity)   |
  | `:bucket_ms`           | `pos_integer` / `1_000`          | Width of each sub-bucket       |
  | `:max_window_ms`       | `pos_integer` / `bucket_ms * 60` | Oldest data retained; cutoff   |
  | `:cleanup_interval_ms` | `pos_integer`/`:infinity`/`60_000` | Background cleanup interval   |
  | `:name`                | atom / `nil`                     | Optional registration name     |
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

    bucket_ms = Keyword.get(opts, :bucket_ms, @default_bucket_ms)
    max_window_ms = Keyword.get(opts, :max_window_ms, bucket_ms * @default_max_window_buckets)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{
      clock: clock,
      bucket_ms: bucket_ms,
      max_window_ms: max_window_ms,
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
    now = state.clock.()
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

  def handle_info(:cleanup, state) do
    # TODO
  end

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
    now = state.clock.()
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
```

Reply with `handle_info` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
