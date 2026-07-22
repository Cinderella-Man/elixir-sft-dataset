defmodule SlidingAlerterTest do
  use ExUnit.Case, async: false

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
      SlidingAlerter.start_link(
        clock: &Clock.now/0,
        bucket_ms: 100,
        threshold: 3,
        window_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    %{sc: pid}
  end

  test "unknown key has count zero and status :ok", %{sc: sc} do
    assert 0 = SlidingAlerter.count(sc, "new_key")
    assert :ok = SlidingAlerter.status(sc, "new_key")
  end

  test "below threshold the status stays :ok", %{sc: sc} do
    assert :ok = SlidingAlerter.record(sc, "k")
    assert :ok = SlidingAlerter.record(sc, "k")
    assert :ok = SlidingAlerter.status(sc, "k")
    assert 2 = SlidingAlerter.count(sc, "k")
  end

  test "reaching the threshold puts the key in alarm", %{sc: sc} do
    assert :ok = SlidingAlerter.record(sc, "k")
    assert :ok = SlidingAlerter.record(sc, "k")
    # The third event reaches threshold 3 -> alarm.
    assert :alarm = SlidingAlerter.record(sc, "k")
    assert :alarm = SlidingAlerter.status(sc, "k")
    assert 3 = SlidingAlerter.count(sc, "k")
  end

  test "status stays in alarm while count remains at or above threshold", %{sc: sc} do
    for _ <- 1..3, do: SlidingAlerter.record(sc, "k")
    assert :alarm = SlidingAlerter.record(sc, "k")
    assert 4 = SlidingAlerter.count(sc, "k")
  end

  test "alarm self-clears as events slide out of the window", %{sc: sc} do
    for _ <- 1..3, do: SlidingAlerter.record(sc, "k")
    assert :alarm = SlidingAlerter.status(sc, "k")

    # Advance past the alerting window so all three events expire.
    Clock.advance(1_001)
    assert 0 = SlidingAlerter.count(sc, "k")
    assert :ok = SlidingAlerter.status(sc, "k")
  end

  test "count only includes events within the window", %{sc: sc} do
    SlidingAlerter.record(sc, "k")
    Clock.advance(500)
    SlidingAlerter.record(sc, "k")
    assert 2 = SlidingAlerter.count(sc, "k")

    # Advance so the first event (now 1_100ms old) falls outside the 1_000ms window.
    Clock.advance(600)
    assert 1 = SlidingAlerter.count(sc, "k")
  end

  test "keys are tracked independently", %{sc: sc} do
    for _ <- 1..3, do: SlidingAlerter.record(sc, "a")
    SlidingAlerter.record(sc, "b")

    assert :alarm = SlidingAlerter.status(sc, "a")
    assert :ok = SlidingAlerter.status(sc, "b")
  end

  test "expired keys are removed during cleanup", %{sc: sc} do
    for i <- 1..50 do
      SlidingAlerter.record(sc, "key:#{i}")
    end

    Clock.advance(10_000)
    send(sc, :cleanup)

    # A subsequent synchronous call is processed after the :cleanup message,
    # so every expired key is observably empty through the public API.
    for i <- 1..50 do
      assert 0 = SlidingAlerter.count(sc, "key:#{i}")
      assert :ok = SlidingAlerter.status(sc, "key:#{i}")
    end
  end

  test "active keys survive cleanup", %{sc: sc} do
    SlidingAlerter.record(sc, "active")
    send(sc, :cleanup)

    # The count call is handled after :cleanup, confirming the live key remains.
    assert 1 = SlidingAlerter.count(sc, "active")
  end

  test "bucket whose start equals now minus window_ms is still counted", %{sc: sc} do
    # Event at t=0 lands in bucket 0, whose start time is 0.
    SlidingAlerter.record(sc, "edge")

    # now - window_ms == 0, so bucket 0 sits exactly on the boundary and counts.
    Clock.set(1_000)
    assert 1 = SlidingAlerter.count(sc, "edge")
    assert :ok = SlidingAlerter.status(sc, "edge")

    # One millisecond later the cutoff is 1, so bucket 0 drops out.
    Clock.set(1_001)
    assert 0 = SlidingAlerter.count(sc, "edge")
  end

  test "event is excluded once its bucket start falls out even if the event is younger", %{sc: sc} do
    Clock.set(199)
    SlidingAlerter.record(sc, "bkt")

    # The event is only 951ms old (inside the 1_000ms window by event time), but it
    # lives in bucket 1 whose start time is 100, and the cutoff is now 150.
    Clock.set(1_150)
    assert 0 = SlidingAlerter.count(sc, "bkt")
    assert :ok = SlidingAlerter.status(sc, "bkt")
  end

  test "default threshold requires five events in the window before alarm" do
    {:ok, pid} = SlidingAlerter.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    for _ <- 1..4 do
      assert :ok = SlidingAlerter.record(pid, "d")
    end

    assert 4 = SlidingAlerter.count(pid, "d")
    assert :alarm = SlidingAlerter.record(pid, "d")
    assert 5 = SlidingAlerter.count(pid, "d")
  end

  test "default window and bucket widths keep an event for a full minute" do
    {:ok, pid} = SlidingAlerter.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    # Default bucket_ms is 1_000, so the event at t=0 lands in bucket 0 (start 0).
    SlidingAlerter.record(pid, "d")

    # Default window_ms is 60_000: cutoff is 0 and the bucket is still inside.
    Clock.set(60_000)
    assert 1 = SlidingAlerter.count(pid, "d")

    # Cutoff is now 1_000, past the start of bucket 0.
    Clock.set(61_000)
    assert 0 = SlidingAlerter.count(pid, "d")
  end

  test "the :name option registers the process so the API works through the name" do
    {:ok, _pid} =
      SlidingAlerter.start_link(
        name: :sliding_alerter_named,
        clock: &Clock.now/0,
        bucket_ms: 100,
        threshold: 2,
        window_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    assert :ok = SlidingAlerter.record(:sliding_alerter_named, "n")
    assert :alarm = SlidingAlerter.record(:sliding_alerter_named, "n")
    assert 2 = SlidingAlerter.count(:sliding_alerter_named, "n")
    assert :alarm = SlidingAlerter.status(:sliding_alerter_named, "n")
  end
end
