# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule SlidingCounterTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      SlidingCounter.start_link(
        clock: &Clock.now/0,
        bucket_ms: 100,
        cleanup_interval_ms: :infinity
      )

    %{sc: pid}
  end

  # -------------------------------------------------------
  # Basic increment / count
  # -------------------------------------------------------

  test "count is zero for a key that has never been incremented", %{sc: sc} do
    assert 0 = SlidingCounter.count(sc, "new_key", 1_000)
  end

  test "single increment is counted within the window", %{sc: sc} do
    SlidingCounter.increment(sc, "k")
    assert 1 = SlidingCounter.count(sc, "k", 1_000)
  end

  test "multiple increments are all counted within the window", %{sc: sc} do
    for _ <- 1..5, do: SlidingCounter.increment(sc, "k")
    assert 5 = SlidingCounter.count(sc, "k", 1_000)
  end

  # -------------------------------------------------------
  # Sliding window boundary
  # -------------------------------------------------------

  test "events outside the window are not counted", %{sc: sc} do
    # Increment at time 0
    SlidingCounter.increment(sc, "k")

    # Advance past the window
    Clock.advance(1_001)

    assert 0 = SlidingCounter.count(sc, "k", 1_000)
  end

  test "events exactly at the window boundary are counted", %{sc: sc} do
    SlidingCounter.increment(sc, "k")

    # Advance to just inside the window
    Clock.advance(999)

    assert 1 = SlidingCounter.count(sc, "k", 1_000)
  end

  test "sliding window counts only recent events", %{sc: sc} do
    # Time 0: 2 increments
    SlidingCounter.increment(sc, "k")
    SlidingCounter.increment(sc, "k")

    # Time 600: 3 more increments
    Clock.advance(600)
    SlidingCounter.increment(sc, "k")
    SlidingCounter.increment(sc, "k")
    SlidingCounter.increment(sc, "k")

    # Time 1_050: first two (from t=0) have expired, last three (from t=600) remain
    Clock.advance(450)
    assert 3 = SlidingCounter.count(sc, "k", 1_000)
  end

  test "count drops to zero once all events expire", %{sc: sc} do
    for _ <- 1..4, do: SlidingCounter.increment(sc, "k")

    Clock.advance(2_000)

    assert 0 = SlidingCounter.count(sc, "k", 1_000)
  end

  # -------------------------------------------------------
  # Key independence
  # -------------------------------------------------------

  test "different keys are completely independent", %{sc: sc} do
    for _ <- 1..3, do: SlidingCounter.increment(sc, "a")
    for _ <- 1..7, do: SlidingCounter.increment(sc, "b")

    assert 3 = SlidingCounter.count(sc, "a", 1_000)
    assert 7 = SlidingCounter.count(sc, "b", 1_000)
  end

  test "expiring one key does not affect another", %{sc: sc} do
    SlidingCounter.increment(sc, "a")

    Clock.advance(500)
    SlidingCounter.increment(sc, "b")

    # Advance so "a" expires but "b" is still in window
    Clock.advance(600)

    assert 0 = SlidingCounter.count(sc, "a", 1_000)
    assert 1 = SlidingCounter.count(sc, "b", 1_000)
  end

  # -------------------------------------------------------
  # Sub-bucket recycling / no memory leaks
  # -------------------------------------------------------

  test "expired keys are removed during cleanup", %{sc: sc} do
    # TODO
  end

  test "active keys survive cleanup", %{sc: sc} do
    SlidingCounter.increment(sc, "active")

    send(sc, :cleanup)

    # The synchronous count runs after the :cleanup message has been handled,
    # and the fresh event is still inside the retention horizon.
    assert 1 = SlidingCounter.count(sc, "active", 60_000)
  end

  test "sub-buckets for a key are pruned as the window slides", %{sc: sc} do
    # Spread increments across many buckets
    for i <- 0..9 do
      Clock.set(i * 200)
      SlidingCounter.increment(sc, "k")
    end

    # At t=2000, window of 1000ms covers buckets from t=1000 onward (5 events)
    Clock.set(2_000)
    assert 5 = SlidingCounter.count(sc, "k", 1_000)
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "window_ms smaller than bucket_ms still works", %{sc: sc} do
    SlidingCounter.increment(sc, "k")
    # A 50ms window with 100ms buckets — event is still in the current bucket
    assert 1 = SlidingCounter.count(sc, "k", 50)

    Clock.advance(150)
    assert 0 = SlidingCounter.count(sc, "k", 50)
  end

  test "very large window includes all increments", %{sc: sc} do
    for i <- 0..4 do
      Clock.set(i * 10_000)
      SlidingCounter.increment(sc, "k")
    end

    Clock.set(40_000)
    assert 5 = SlidingCounter.count(sc, "k", 86_400_000)
  end

  test "interleaved increments across keys at different times", %{sc: sc} do
    Clock.set(0)
    SlidingCounter.increment(sc, "x")

    Clock.set(300)
    SlidingCounter.increment(sc, "y")
    SlidingCounter.increment(sc, "x")

    Clock.set(700)
    SlidingCounter.increment(sc, "y")

    # At t=1100, "x" t=0 expired, "x" t=300 still in; both "y" still in
    Clock.set(1_100)
    assert 1 = SlidingCounter.count(sc, "x", 1_000)
    assert 2 = SlidingCounter.count(sc, "y", 1_000)
  end

  # -------------------------------------------------------
  # Documented defaults, observed through the public API
  # (clock injection + the :cleanup message contract; a
  # synchronous count/3 after send/2 is the mailbox barrier)
  # -------------------------------------------------------

  test "default bucket_ms is 1000: an event at t=1000 starts a new bucket", %{sc: _sc} do
    {:ok, pid} =
      SlidingCounter.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    Clock.set(1_000)
    SlidingCounter.increment(pid, "k")

    # Bucket 1 starts exactly at 1000, so even a 1 ms window still sees it:
    # the cutoff quantizes to bucket starts and the old side is inclusive.
    assert 1 = SlidingCounter.count(pid, "k", 1)
  end

  test "default bucket_ms is 1000: an event at t=999 belongs to the bucket at 0", %{sc: _sc} do
    {:ok, pid} =
      SlidingCounter.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    Clock.set(999)
    SlidingCounter.increment(pid, "k")
    Clock.set(1_999)

    # Bucket 0 (starting at time 0) now lies entirely outside a 1000 ms window.
    assert 0 = SlidingCounter.count(pid, "k", 1_000)
  end

  test "default retention is exactly 60 buckets of history", %{sc: sc} do
    SlidingCounter.increment(sc, "old")

    # 59.5 bucket-widths later, the event's bucket is still inside bucket_ms * 60.
    Clock.set(5_950)
    send(sc, :cleanup)
    assert 1 = SlidingCounter.count(sc, "old", 100_000)

    # 60.5 bucket-widths later it has aged past the default horizon; cleanup drops it.
    Clock.set(6_050)
    send(sc, :cleanup)
    assert 0 = SlidingCounter.count(sc, "old", 100_000)
  end

  test "cleanup keeps the bucket sitting exactly on the retention boundary", %{sc: _sc} do
    {:ok, pid} =
      SlidingCounter.start_link(
        clock: &Clock.now/0,
        bucket_ms: 100,
        max_window_ms: 500,
        cleanup_interval_ms: :infinity
      )

    SlidingCounter.increment(pid, "edge")

    # At now = 500 the bucket starting at 0 sits exactly on the horizon. A count
    # over the full 500 ms window still sees it, and cleanup must never delete
    # data a legal count could still return — so it must survive the pass.
    Clock.set(500)
    send(pid, :cleanup)
    assert 1 = SlidingCounter.count(pid, "edge", 500)
  end

  test "negative clock times bucket by floor division and slide correctly", %{sc: sc} do
    Clock.set(-250)
    SlidingCounter.increment(sc, "neg")

    # now = -250, window 100 => window_start = -350; the bucket [-300, -200) starts
    # at -300 >= -350, so it counts.
    assert 1 = SlidingCounter.count(sc, "neg", 100)

    # Crossing zero: an event at -50 sits in bucket [-100, 0) and is still visible
    # from now = 0 with a 100 ms window (bucket start -100 >= -100).
    Clock.set(-50)
    SlidingCounter.increment(sc, "cross")
    Clock.set(0)
    assert 1 = SlidingCounter.count(sc, "cross", 100)

    # The old -250 event's bucket starts at -300, well before 0 - 100, so it is gone.
    assert 0 = SlidingCounter.count(sc, "neg", 100)
  end

  test "stray messages neither crash the counter nor alter its counts", %{sc: sc} do
    SlidingCounter.increment(sc, "k")
    SlidingCounter.increment(sc, "k")

    send(sc, :not_cleanup)
    send(sc, {:unrelated, self(), make_ref()})
    send(sc, "a stray binary")

    # The synchronous call is the mailbox barrier: it runs after every stray
    # message above has been handled.
    assert 2 = SlidingCounter.count(sc, "k", 1_000)
    assert Process.alive?(sc)
  end

  test "name option registers the process and is not treated as counter config", %{sc: _sc} do
    name = :sliding_counter_named_instance

    {:ok, pid} =
      SlidingCounter.start_link(
        name: name,
        clock: &Clock.now/0,
        bucket_ms: 100,
        cleanup_interval_ms: :infinity
      )

    # Registered: the name works as a server reference and behaves normally.
    assert :ok = SlidingCounter.increment(name, "k")
    assert 1 = SlidingCounter.count(name, "k", 1_000)

    # Forwarded as a start option, so a second start under the same name reports
    # the standard GenServer.on_start() error rather than starting a twin.
    assert {:error, {:already_started, ^pid}} =
             SlidingCounter.start_link(
               name: name,
               clock: &Clock.now/0,
               cleanup_interval_ms: :infinity
             )
  end

  test "bucket starting exactly at now minus window_ms is included, one ms later excluded", %{
    sc: sc
  } do
    SlidingCounter.increment(sc, "edge")

    # Bucket 0 starts at 0; at now = 500 with a 500 ms window, window_start = 0,
    # so the bucket start is exactly on the inclusive old edge.
    Clock.set(500)
    assert 1 = SlidingCounter.count(sc, "edge", 500)

    # One millisecond later window_start = 1 > 0, so the bucket contributes nothing
    # at all even though its range overlaps the leading edge.
    Clock.set(501)
    assert 0 = SlidingCounter.count(sc, "edge", 500)
  end

  test "arbitrary terms work as keys and are matched by value", %{sc: sc} do
    tuple_key = {:page, 1, ["a"]}
    equal_tuple_key = {:page, 1, ["a"]}
    other_tuple_key = {:page, 2, ["a"]}

    SlidingCounter.increment(sc, tuple_key)
    SlidingCounter.increment(sc, equal_tuple_key)
    SlidingCounter.increment(sc, :atom_key)
    SlidingCounter.increment(sc, other_tuple_key)

    # The value-equal tuple is the same key, so both increments land together.
    assert 2 = SlidingCounter.count(sc, equal_tuple_key, 1_000)
    assert 1 = SlidingCounter.count(sc, :atom_key, 1_000)
    assert 1 = SlidingCounter.count(sc, other_tuple_key, 1_000)
    assert 0 = SlidingCounter.count(sc, "page", 1_000)
  end

  test "repeated counts with an unchanged clock are stable and non-destructive", %{sc: sc} do
    for _ <- 1..3, do: SlidingCounter.increment(sc, "k")

    # Counting an unknown key must not create an entry or disturb anything.
    assert 0 = SlidingCounter.count(sc, "ghost", 1_000)
    assert 0 = SlidingCounter.count(sc, "ghost", 1_000)

    assert 3 = SlidingCounter.count(sc, "k", 1_000)
    assert 3 = SlidingCounter.count(sc, "k", 1_000)
    assert 3 = SlidingCounter.count(sc, "k", 1_000)

    # Reads left the data intact: a later increment adds to it rather than
    # rebuilding a drained key.
    assert :ok = SlidingCounter.increment(sc, "k")
    assert 4 = SlidingCounter.count(sc, "k", 1_000)
  end

  # -------------------------------------------------------
  # The periodic cleanup timer, observed without ever sending
  # :cleanup ourselves: the process must arm a timer during
  # init/1 and re-arm it after every handled cleanup.
  # -------------------------------------------------------

  test "cleanup runs on its own timer and keeps re-arming for later rounds", %{sc: _sc} do
    interval = 25
    # Generously wider than the interval so a slow scheduler is not mistaken
    # for a missing one; only a server that never fires can exhaust it.
    deadline_ms = 20 * interval

    Clock.set(0)

    {:ok, pid} =
      SlidingCounter.start_link(
        clock: &Clock.now/0,
        bucket_ms: 100,
        max_window_ms: 500,
        cleanup_interval_ms: interval
      )

    SlidingCounter.increment(pid, "auto")

    # Still live: a wide window sees the event until cleanup physically drops it.
    assert 1 = SlidingCounter.count(pid, "auto", 100_000)

    # Push the clock far past the retention horizon and wait for the timer, which
    # nobody triggered by hand, to evict the aged bucket.
    Clock.set(10_000)

    assert poll_until(fn -> SlidingCounter.count(pid, "auto", 100_000) == 0 end, deadline_ms),
           "the periodic timer never fired a first automatic cleanup"

    # Second round: a fresh event that ages out afterwards can only be dropped by
    # a timer that was re-armed after the first cleanup was handled.
    Clock.set(20_000)
    SlidingCounter.increment(pid, "auto2")
    assert 1 = SlidingCounter.count(pid, "auto2", 100_000)

    Clock.set(40_000)

    assert poll_until(fn -> SlidingCounter.count(pid, "auto2", 100_000) == 0 end, deadline_ms),
           "the periodic timer did not re-arm after handling a cleanup"
  end

  # Repeatedly evaluates `fun` until it returns true or the deadline elapses,
  # reporting whether the condition was ever observed.
  defp poll_until(fun, timeout_ms) do
    poll_loop(fun, System.monotonic_time(:millisecond) + timeout_ms)
  end

  defp poll_loop(fun, deadline) do
    cond do
      fun.() -> true
      System.monotonic_time(:millisecond) >= deadline -> false
      true -> poll_loop(fun, deadline)
    end
  end
end
```
