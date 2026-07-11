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
end
