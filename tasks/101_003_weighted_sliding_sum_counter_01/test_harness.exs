defmodule SlidingSumTest do
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
      SlidingSum.start_link(
        clock: &Clock.now/0,
        bucket_ms: 100,
        cleanup_interval_ms: :infinity
      )

    %{sc: pid}
  end

  test "sum is zero for a key that has had nothing added", %{sc: sc} do
    assert 0 == SlidingSum.sum(sc, "new_key", 1_000)
  end

  test "a single amount is summed within the window", %{sc: sc} do
    SlidingSum.add(sc, "k", 5)
    assert 5 == SlidingSum.sum(sc, "k", 1_000)
  end

  test "multiple amounts are summed within the window", %{sc: sc} do
    SlidingSum.add(sc, "k", 3)
    SlidingSum.add(sc, "k", 4)
    assert 7 == SlidingSum.sum(sc, "k", 1_000)
  end

  test "float amounts are summed", %{sc: sc} do
    SlidingSum.add(sc, "k", 2.5)
    SlidingSum.add(sc, "k", 1.5)
    assert 4.0 == SlidingSum.sum(sc, "k", 1_000)
  end

  test "negative amounts subtract from the running sum", %{sc: sc} do
    SlidingSum.add(sc, "k", 10)
    SlidingSum.add(sc, "k", -3)
    assert 7 == SlidingSum.sum(sc, "k", 1_000)
  end

  test "amounts outside the window are not included", %{sc: sc} do
    SlidingSum.add(sc, "k", 5)
    Clock.advance(1_001)
    assert 0 == SlidingSum.sum(sc, "k", 1_000)
  end

  test "bucket whose start is within the window is included", %{sc: sc} do
    SlidingSum.add(sc, "k", 5)
    Clock.advance(999)
    assert 5 == SlidingSum.sum(sc, "k", 1_000)
  end

  test "sliding window sums only recent amounts", %{sc: sc} do
    SlidingSum.add(sc, "k", 2)

    Clock.advance(600)
    SlidingSum.add(sc, "k", 5)

    # At t=1050, the amount from t=0 (bucket 0) has slid out; only the 5 remains.
    Clock.advance(450)
    assert 5 == SlidingSum.sum(sc, "k", 1_000)
  end

  test "sum drops to zero once all amounts expire", %{sc: sc} do
    SlidingSum.add(sc, "k", 9)
    Clock.advance(2_000)
    assert 0 == SlidingSum.sum(sc, "k", 1_000)
  end

  test "different keys are completely independent", %{sc: sc} do
    SlidingSum.add(sc, "a", 3)
    SlidingSum.add(sc, "b", 7)

    assert 3 == SlidingSum.sum(sc, "a", 1_000)
    assert 7 == SlidingSum.sum(sc, "b", 1_000)
  end

  test "expired keys are removed during cleanup", %{sc: sc} do
    for i <- 1..50 do
      SlidingSum.add(sc, "key:#{i}", i)
    end

    # Advance past the cleanup's maximum retention window (24 hours) so every
    # bucket is guaranteed to have expired.
    Clock.advance(24 * 60 * 60 * 1_000 + 1_000)
    send(sc, :cleanup)

    # The follow-up call is processed after the :cleanup message, so it acts as
    # a synchronization barrier and observes the post-cleanup key set.
    assert SlidingSum.keys(sc) == []
  end

  test "active keys survive cleanup", %{sc: sc} do
    SlidingSum.add(sc, "active", 42)
    send(sc, :cleanup)

    # The sum/3 call is processed after :cleanup, acting as a barrier, and the
    # active key must still be present.
    assert 42 == SlidingSum.sum(sc, "active", 60_000)
    assert SlidingSum.keys(sc) == ["active"]
  end
end
