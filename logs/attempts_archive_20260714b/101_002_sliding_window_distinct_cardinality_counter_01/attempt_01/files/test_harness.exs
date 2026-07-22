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

  test "members exactly at the window boundary are counted", %{sc: sc} do
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
    for m <- ["a1", "a2", "a3"], do: SlidingUniqueCounter.add(sc, "a", m)
    for m <- ["b1", "b2", "b3", "b4", "b5", "b6", "b7"], do: SlidingUniqueCounter.add(sc, "b", m)

    assert 3 = SlidingUniqueCounter.distinct_count(sc, "a", 1_000)
    assert 7 = SlidingUniqueCounter.distinct_count(sc, "b", 1_000)
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
    :sys.get_state(sc)

    state = :sys.get_state(sc)
    assert map_size(state.keys) == 0
  end

  test "active keys survive cleanup", %{sc: sc} do
    SlidingUniqueCounter.add(sc, "active", "u1")

    send(sc, :cleanup)
    :sys.get_state(sc)

    assert 1 = SlidingUniqueCounter.distinct_count(sc, "active", 60_000)
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
end
