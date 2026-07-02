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
    for i <- 1..50 do
      SlidingCounter.increment(sc, "key:#{i}")
    end

    # Let all windows expire
    Clock.advance(10_000)

    send(sc, :cleanup)
    :sys.get_state(sc)

    state = :sys.get_state(sc)
    assert map_size(state.keys) == 0
  end

  test "active keys survive cleanup", %{sc: sc} do
    SlidingCounter.increment(sc, "active")

    send(sc, :cleanup)
    :sys.get_state(sc)

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
end
