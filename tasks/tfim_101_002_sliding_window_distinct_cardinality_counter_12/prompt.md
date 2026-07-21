# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule SlidingUniqueCounter do
  @moduledoc """
  A GenServer that tracks the number of **distinct members** seen for a key
  within a sliding time window, using a fixed-width sub-bucket strategy.

  Unlike a plain event counter, this counter answers "how many *unique* things
  did we see", not "how many events happened". Adding the same member many
  times inside the window still counts that member exactly once.

  ## Design

  Time is divided into fixed-width sub-buckets of `:bucket_ms` milliseconds.
  Every observation is placed into the bucket whose index is
  `div(timestamp, bucket_ms)`. Each bucket stores the `MapSet` of distinct
  members observed inside it. A `distinct_count/3` query unions the member sets
  of every in-window bucket and returns the size of that union, so a member
  observed in several in-window buckets is still counted once.

  Different keys are tracked independently. A periodic cleanup removes buckets
  (and whole keys) that have fallen outside a maximum retention window so that
  memory does not grow without bound.
  """

  use GenServer

  @default_bucket_ms 1_000
  @default_cleanup_interval_ms 60_000
  @default_max_window_ms 3_600_000

  @type key :: term()
  @type member :: term()
  @type server :: GenServer.server()

  @typep state :: %{
           clock: (-> integer()),
           bucket_ms: pos_integer(),
           cleanup_interval_ms: pos_integer() | :infinity,
           max_window_ms: pos_integer(),
           keys: %{optional(key()) => %{optional(integer()) => MapSet.t()}}
         }

  @doc """
  Starts the counter process.

  ## Options

    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:bucket_ms` — the width of each internal sub-bucket in milliseconds.
      Defaults to `1_000`.
    * `:name` — optional process registration name.
    * `:cleanup_interval_ms` — how often to run the periodic cleanup.
      Defaults to `60_000`. Pass `:infinity` to disable.
    * `:max_window_ms` — buckets older than this relative to the current clock
      time are discarded during cleanup. Defaults to `3_600_000`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Records that `member` was observed for `key` at the current clock time.

  Always returns `:ok`.
  """
  @spec add(server(), key(), member()) :: :ok
  def add(server, key, member) do
    GenServer.call(server, {:add, key, member})
  end

  @doc """
  Returns the number of **distinct** members observed for `key` that fall
  within the last `window_ms` milliseconds relative to the current clock time.

  Members observed only outside that window are not counted. A member observed
  in more than one in-window bucket is counted once (the union of all in-window
  buckets).
  """
  @spec distinct_count(server(), key(), non_neg_integer()) :: non_neg_integer()
  def distinct_count(server, key, window_ms) do
    GenServer.call(server, {:distinct_count, key, window_ms})
  end

  @doc """
  Returns the number of keys currently retained by the counter.

  A key is retained only while it still holds at least one bucket. Once cleanup
  discards a key's last remaining bucket, the key is dropped entirely and no
  longer counted here. This exposes retained storage through the public API so
  callers can assert that memory does not leak.
  """
  @spec tracked_key_count(server()) :: non_neg_integer()
  def tracked_key_count(server) do
    GenServer.call(server, :tracked_key_count)
  end

  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    bucket_ms = Keyword.get(opts, :bucket_ms, @default_bucket_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    max_window_ms = Keyword.get(opts, :max_window_ms, @default_max_window_ms)

    state = %{
      clock: clock,
      bucket_ms: bucket_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      max_window_ms: max_window_ms,
      keys: %{}
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:add, key, member}, _from, state) do
    now = state.clock.()
    index = div(now, state.bucket_ms)

    buckets = Map.get(state.keys, key, %{})
    set = Map.get(buckets, index, MapSet.new())
    buckets = Map.put(buckets, index, MapSet.put(set, member))
    keys = Map.put(state.keys, key, buckets)

    {:reply, :ok, %{state | keys: keys}}
  end

  def handle_call({:distinct_count, key, window_ms}, _from, state) do
    now = state.clock.()
    threshold = now - window_ms
    buckets = Map.get(state.keys, key, %{})

    union =
      Enum.reduce(buckets, MapSet.new(), fn {index, set}, acc ->
        if index * state.bucket_ms >= threshold do
          MapSet.union(acc, set)
        else
          acc
        end
      end)

    {:reply, MapSet.size(union), state}
  end

  def handle_call(:tracked_key_count, _from, state) do
    {:reply, map_size(state.keys), state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    state = purge_expired(state)
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @spec schedule_cleanup(pos_integer() | :infinity) :: :ok
  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
    :ok
  end

  @spec purge_expired(state()) :: state()
  defp purge_expired(state) do
    now = state.clock.()
    threshold = now - state.max_window_ms

    keys =
      Enum.reduce(state.keys, %{}, fn {key, buckets}, acc ->
        kept =
          Enum.reduce(buckets, %{}, fn {index, set}, inner ->
            if index * state.bucket_ms >= threshold do
              Map.put(inner, index, set)
            else
              inner
            end
          end)

        if map_size(kept) == 0, do: acc, else: Map.put(acc, key, kept)
      end)

    %{state | keys: keys}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule SlidingUniqueCounterTest do
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
      SlidingUniqueCounter.start_link(
        clock: &Clock.now/0,
        bucket_ms: 100,
        cleanup_interval_ms: :infinity,
        max_window_ms: 1_000
      )

    %{sc: pid}
  end

  # -------------------------------------------------------
  # Basic add / distinct_count
  # -------------------------------------------------------

  test "distinct_count is zero for a key that has never been added", %{sc: sc} do
    assert 0 = SlidingUniqueCounter.distinct_count(sc, "new_key", 1_000)
  end

  test "single member is counted within the window", %{sc: sc} do
    SlidingUniqueCounter.add(sc, "k", "u1")
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end

  test "the same member added twice counts once", %{sc: sc} do
    SlidingUniqueCounter.add(sc, "k", "u1")
    SlidingUniqueCounter.add(sc, "k", "u1")
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end

  test "distinct members are all counted within the window", %{sc: sc} do
    for m <- ["u1", "u2", "u3", "u4", "u5"] do
      SlidingUniqueCounter.add(sc, "k", m)
    end

    assert 5 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end

  test "repeated members among distinct ones are deduplicated", %{sc: sc} do
    for m <- ["u1", "u2", "u1", "u3", "u2", "u1"] do
      SlidingUniqueCounter.add(sc, "k", m)
    end

    assert 3 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end

  # -------------------------------------------------------
  # Sliding window boundary
  # -------------------------------------------------------

  test "members observed only outside the window are not counted", %{sc: sc} do
    SlidingUniqueCounter.add(sc, "k", "u1")

    # Advance past the window
    Clock.advance(1_001)

    assert 0 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end

  test "members just inside the window boundary are counted", %{sc: sc} do
    SlidingUniqueCounter.add(sc, "k", "u1")

    # Advance to just inside the window
    Clock.advance(999)

    assert 1 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end

  test "sliding window counts only recently seen distinct members", %{sc: sc} do
    # Time 0: u1, u2
    SlidingUniqueCounter.add(sc, "k", "u1")
    SlidingUniqueCounter.add(sc, "k", "u2")

    # Time 600: u3, u4
    Clock.advance(600)
    SlidingUniqueCounter.add(sc, "k", "u3")
    SlidingUniqueCounter.add(sc, "k", "u4")

    # Time 1_050: u1/u2 (bucket at t=0) have expired, u3/u4 remain
    Clock.advance(450)
    assert 2 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end

  test "member seen in both an expired and a live bucket counts once", %{sc: sc} do
    # Time 0: u1 observed (will expire)
    SlidingUniqueCounter.add(sc, "k", "u1")

    # Time 600: u1 observed again (stays live)
    Clock.advance(600)
    SlidingUniqueCounter.add(sc, "k", "u1")

    # Time 1_050: only the t=600 observation is in-window; union = {u1}
    Clock.advance(450)
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end

  test "distinct_count drops to zero once all observations expire", %{sc: sc} do
    for m <- ["u1", "u2", "u3", "u4"] do
      SlidingUniqueCounter.add(sc, "k", m)
    end

    Clock.advance(2_000)

    assert 0 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end

  # -------------------------------------------------------
  # Key independence
  # -------------------------------------------------------

  test "different keys are completely independent", %{sc: sc} do
    # TODO
  end

  test "the same member string under two keys is counted per key", %{sc: sc} do
    SlidingUniqueCounter.add(sc, "a", "shared")
    SlidingUniqueCounter.add(sc, "b", "shared")

    assert 1 = SlidingUniqueCounter.distinct_count(sc, "a", 1_000)
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "b", 1_000)
  end

  test "expiring one key does not affect another", %{sc: sc} do
    SlidingUniqueCounter.add(sc, "a", "u1")

    Clock.advance(500)
    SlidingUniqueCounter.add(sc, "b", "u1")

    # Advance so "a" expires but "b" is still in window
    Clock.advance(600)

    assert 0 = SlidingUniqueCounter.distinct_count(sc, "a", 1_000)
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "b", 1_000)
  end

  # -------------------------------------------------------
  # Cleanup / no memory leaks
  # -------------------------------------------------------

  test "expired keys are removed during cleanup", %{sc: sc} do
    for i <- 1..50 do
      SlidingUniqueCounter.add(sc, "key:#{i}", "m#{i}")
    end

    # Let all windows expire
    Clock.advance(10_000)

    send(sc, :cleanup)

    # A subsequent GenServer call is processed after :cleanup, so this
    # observes state through the public API once cleanup has run.
    assert SlidingUniqueCounter.tracked_key_count(sc) == 0
  end

  test "active keys survive cleanup", %{sc: sc} do
    SlidingUniqueCounter.add(sc, "active", "u1")

    send(sc, :cleanup)

    # distinct_count is a synchronous call ordered after :cleanup, so this
    # both flushes the cleanup message and checks observable behavior.
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "active", 60_000)
    assert SlidingUniqueCounter.tracked_key_count(sc) == 1
  end

  test "distinct members are pruned as the window slides", %{sc: sc} do
    # Spread distinct members across many buckets
    for i <- 0..9 do
      Clock.set(i * 200)
      SlidingUniqueCounter.add(sc, "k", "u#{i}")
    end

    # At t=2000, a 1000ms window covers buckets whose start >= 1000 (u5..u9)
    Clock.set(2_000)
    assert 5 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "window_ms smaller than bucket_ms still works", %{sc: sc} do
    SlidingUniqueCounter.add(sc, "k", "u1")
    # A 50ms window with 100ms buckets — member is still in the current bucket
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "k", 50)

    Clock.advance(150)
    assert 0 = SlidingUniqueCounter.distinct_count(sc, "k", 50)
  end

  test "very large window includes all distinct members", %{sc: sc} do
    for i <- 0..4 do
      Clock.set(i * 10_000)
      SlidingUniqueCounter.add(sc, "k", "u#{i}")
    end

    Clock.set(40_000)
    assert 5 = SlidingUniqueCounter.distinct_count(sc, "k", 86_400_000)
  end

  test "interleaved adds across keys at different times", %{sc: sc} do
    Clock.set(0)
    SlidingUniqueCounter.add(sc, "x", "x1")

    Clock.set(300)
    SlidingUniqueCounter.add(sc, "y", "y1")
    SlidingUniqueCounter.add(sc, "x", "x2")

    Clock.set(700)
    SlidingUniqueCounter.add(sc, "y", "y2")

    # At t=1100, "x1" (t=0) expired, "x2" still in; both "y" members still in
    Clock.set(1_100)
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "x", 1_000)
    assert 2 = SlidingUniqueCounter.distinct_count(sc, "y", 1_000)
  end

  # -------------------------------------------------------
  # Periodic (self-scheduled) cleanup
  # -------------------------------------------------------

  test "cleanup fires on its own schedule without a directly sent :cleanup" do
    # The counter is given a clock that reports every read back to this test.
    # Once the test stops calling the server, any further clock read can only
    # come from the process waking itself up to run the periodic cleanup.
    {:ok, sc} = start_reporting_counter(cleanup_interval_ms: 20)

    SlidingUniqueCounter.add(sc, "k", "u1")
    assert SlidingUniqueCounter.tracked_key_count(sc) == 1

    flush_clock_reads()
    Clock.advance(10_000)

    await_clock_read_at_least(10_000)
    assert SlidingUniqueCounter.tracked_key_count(sc) == 0
  end

  test "periodic cleanup re-arms itself and purges data that expires later" do
    {:ok, sc} = start_reporting_counter(cleanup_interval_ms: 20)

    SlidingUniqueCounter.add(sc, "k1", "u1")
    flush_clock_reads()
    Clock.advance(10_000)

    await_clock_read_at_least(10_000)
    assert SlidingUniqueCounter.tracked_key_count(sc) == 0

    # Data added after that first purge must be reclaimed by a later cleanup,
    # which only happens if cleanup keeps re-scheduling itself.
    Clock.set(20_000)
    SlidingUniqueCounter.add(sc, "k2", "u2")
    assert SlidingUniqueCounter.tracked_key_count(sc) == 1

    flush_clock_reads()
    Clock.set(40_000)

    await_clock_read_at_least(40_000)
    assert SlidingUniqueCounter.tracked_key_count(sc) == 0
  end

  # -------------------------------------------------------
  # Option defaults and :name registration
  # -------------------------------------------------------

  test "bucket_ms defaults to 1_000" do
    {:ok, sc} =
      SlidingUniqueCounter.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    Clock.set(900)
    SlidingUniqueCounter.add(sc, "k", "early")

    # With 1_000ms buckets, "early" sits in bucket 0, which starts at 0. At
    # now=1_000 a 500ms window keeps only buckets starting at or after 500.
    Clock.set(1_000)
    assert 0 = SlidingUniqueCounter.distinct_count(sc, "k", 500)

    # "late" lands in bucket 1, which starts exactly at 1_000 and so is inside
    # a 1ms window at now=1_000 (threshold 999).
    SlidingUniqueCounter.add(sc, "k", "late")
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "k", 1)
  end

  test "max_window_ms defaults to 3_600_000 as the cleanup retention horizon" do
    {:ok, sc} =
      SlidingUniqueCounter.start_link(
        clock: &Clock.now/0,
        bucket_ms: 100,
        cleanup_interval_ms: :infinity
      )

    Clock.set(0)
    SlidingUniqueCounter.add(sc, "k", "u1")

    # The member's bucket starts at 0; at now=3_600_000 the retention threshold
    # is also 0, so the key is still within the horizon.
    Clock.set(3_600_000)
    send(sc, :cleanup)
    assert SlidingUniqueCounter.tracked_key_count(sc) == 1

    # One bucket later the threshold has moved past the bucket start.
    Clock.set(3_600_101)
    send(sc, :cleanup)
    assert SlidingUniqueCounter.tracked_key_count(sc) == 0
  end

  test "counting works on the default monotonic clock when :clock is omitted" do
    {:ok, sc} = SlidingUniqueCounter.start_link(bucket_ms: 100, cleanup_interval_ms: :infinity)

    SlidingUniqueCounter.add(sc, "k", "u1")
    SlidingUniqueCounter.add(sc, "k", "u1")
    SlidingUniqueCounter.add(sc, "k", "u2")

    assert 2 = SlidingUniqueCounter.distinct_count(sc, "k", 60_000)
  end

  test ":name registers the process so the whole API is usable by name" do
    name = :"sliding_unique_counter_#{System.pid()}_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      SlidingUniqueCounter.start_link(
        name: name,
        clock: &Clock.now/0,
        bucket_ms: 100,
        cleanup_interval_ms: :infinity,
        max_window_ms: 1_000
      )

    assert :ok = SlidingUniqueCounter.add(name, "k", "u1")
    assert :ok = SlidingUniqueCounter.add(name, "k", "u1")
    assert :ok = SlidingUniqueCounter.add(name, "k", "u2")

    assert 2 = SlidingUniqueCounter.distinct_count(name, "k", 1_000)
    assert SlidingUniqueCounter.tracked_key_count(name) == 1
  end

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp start_reporting_counter(opts) do
    test_pid = self()

    clock = fn ->
      now = Clock.now()
      send(test_pid, {:clock_read, now})
      now
    end

    SlidingUniqueCounter.start_link([clock: clock, bucket_ms: 100, max_window_ms: 1_000] ++ opts)
  end

  defp flush_clock_reads do
    receive do
      {:clock_read, _} -> flush_clock_reads()
    after
      0 -> :ok
    end
  end

  defp await_clock_read_at_least(target) do
    receive do
      {:clock_read, now} when now >= target -> :ok
      {:clock_read, _} -> await_clock_read_at_least(target)
    after
      2_000 -> flunk("the counter never read the clock again on its own schedule")
    end
  end

  test "a bucket starting exactly at the window threshold is counted", %{sc: sc} do
    Clock.set(0)
    SlidingUniqueCounter.add(sc, "k", "u1")

    # At now=1_000 with a 1_000ms window the threshold is exactly 0, and the
    # member's bucket starts at 0 — the comparison is `>=`, so it counts.
    Clock.set(1_000)
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end

  test "cleanup_interval_ms :infinity disables the periodic cleanup entirely" do
    {:ok, sc} = start_reporting_counter(cleanup_interval_ms: :infinity)

    SlidingUniqueCounter.add(sc, "k", "u1")
    flush_clock_reads()

    # Move the clock far past the retention horizon. With cleanup disabled the
    # process must never wake itself up, so no further clock read can arrive.
    Clock.advance(10_000)
    refute_receive {:clock_read, _}, 200

    assert SlidingUniqueCounter.tracked_key_count(sc) == 1
  end

  test "cleanup drops only the expired buckets of a key that is still live", %{sc: sc} do
    Clock.set(0)
    SlidingUniqueCounter.add(sc, "k", "old")

    Clock.set(2_000)
    SlidingUniqueCounter.add(sc, "k", "new")

    send(sc, :cleanup)

    # The key survives, but "old" (bucket start 0, outside the 1_000ms horizon)
    # must be gone even when queried through a window wide enough to cover it.
    assert SlidingUniqueCounter.tracked_key_count(sc) == 1
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "k", 100_000)
  end

  test "a member spread across two in-window buckets is unioned to one", %{sc: sc} do
    Clock.set(0)
    SlidingUniqueCounter.add(sc, "k", "u1")

    Clock.set(500)
    SlidingUniqueCounter.add(sc, "k", "u1")
    SlidingUniqueCounter.add(sc, "k", "u2")

    # Buckets 0 and 5 are both in window at now=500; union = {"u1", "u2"}.
    assert 2 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end

  # -------------------------------------------------------
  # Automatic timer-driven cleanup, observed through the public API only
  # -------------------------------------------------------

  test "expired data is purged automatically on a 25ms cleanup interval" do
    {:ok, sc} =
      SlidingUniqueCounter.start_link(
        clock: &Clock.now/0,
        bucket_ms: 100,
        cleanup_interval_ms: 25,
        max_window_ms: 1_000
      )

    Clock.set(0)
    SlidingUniqueCounter.add(sc, "k", "u1")
    assert SlidingUniqueCounter.tracked_key_count(sc) == 1

    # The key is now far outside the retention horizon. Nothing here sends the
    # process a :cleanup message, so tracked_key_count can only reach 0 if the
    # process wakes itself up on the configured interval.
    Clock.set(10_000)

    assert poll_until(fn -> SlidingUniqueCounter.tracked_key_count(sc) == 0 end, 1_000),
           "expired data was never purged by a self-scheduled cleanup"
  end

  test "the automatic cleanup timer re-arms so later data is also reclaimed" do
    {:ok, sc} =
      SlidingUniqueCounter.start_link(
        clock: &Clock.now/0,
        bucket_ms: 100,
        cleanup_interval_ms: 25,
        max_window_ms: 1_000
      )

    Clock.set(0)
    SlidingUniqueCounter.add(sc, "k1", "u1")
    Clock.set(10_000)

    assert poll_until(fn -> SlidingUniqueCounter.tracked_key_count(sc) == 0 end, 1_000),
           "the first self-scheduled cleanup never ran"

    # Data written after that purge must also be reclaimed, which only happens
    # if every cleanup schedules the next one.
    SlidingUniqueCounter.add(sc, "k2", "u2")
    assert SlidingUniqueCounter.tracked_key_count(sc) == 1

    Clock.set(20_000)

    assert poll_until(fn -> SlidingUniqueCounter.tracked_key_count(sc) == 0 end, 1_000),
           "cleanup did not re-schedule itself after its first firing"
  end

  test "cleanup_interval_ms defaults to 60_000 so nothing is purged right away" do
    {:ok, sc} = start_reporting_counter([])

    SlidingUniqueCounter.add(sc, "k", "u1")
    assert SlidingUniqueCounter.tracked_key_count(sc) == 1
    flush_clock_reads()

    # With the default one-minute interval, no cleanup may run in the next few
    # hundred milliseconds, so the process must not read the clock again and
    # the expired key must still be retained.
    Clock.advance(10_000)
    refute_receive {:clock_read, _}, 300

    assert SlidingUniqueCounter.tracked_key_count(sc) == 1
  end

  defp poll_until(fun, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll_until_deadline(fun, deadline)
  end

  defp poll_until_deadline(fun, deadline) do
    cond do
      fun.() -> true
      System.monotonic_time(:millisecond) >= deadline -> false
      true -> poll_until_deadline(fun, deadline)
    end
  end
end
```
