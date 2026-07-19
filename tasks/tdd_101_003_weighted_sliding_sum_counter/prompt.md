# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
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

  # -------------------------------------------------------
  # Documented defaults and boundaries, observed through the
  # public API (injected clock; sum/3 after send/2 as barrier)
  # -------------------------------------------------------

  test "default bucket_ms is 1000: an amount at t=999 belongs to the bucket at 0", %{sc: _sc} do
    {:ok, sc2} = SlidingSum.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    Clock.set(999)
    SlidingSum.add(sc2, "k", 5)
    Clock.set(1_999)

    # Bucket 0 (starting at time 0) lies entirely outside a 1000 ms window now.
    assert 0 == SlidingSum.sum(sc2, "k", 1_000)
  end

  test "default bucket_ms is 1000: an amount at t=1000 starts a new bucket", %{sc: _sc} do
    {:ok, sc2} = SlidingSum.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    Clock.set(1_000)
    SlidingSum.add(sc2, "k", 5)

    # Bucket 1 starts exactly at 1000; the cutoff quantizes to bucket starts
    # and the old side is inclusive, so even a 1 ms window still sees it.
    assert 5 == SlidingSum.sum(sc2, "k", 1)
  end

  test "a zero window is legal and follows the inclusive start-time rule", %{sc: sc} do
    SlidingSum.add(sc, "z", 7)

    # window_ms = 0 means cutoff = now; the current bucket starts at 0 = now,
    # which satisfies bucket_start >= now - 0, so the amount is counted.
    assert 7 == SlidingSum.sum(sc, "z", 0)
  end

  test "a bucket starting exactly at the window cutoff is included", %{sc: sc} do
    SlidingSum.add(sc, "edge", 3)
    Clock.set(1_000)

    # cutoff = 1000 - 1000 = 0; the bucket starts at 0 — inclusive boundary.
    assert 3 == SlidingSum.sum(sc, "edge", 1_000)
  end

  test "cleanup keeps a bucket exactly on the 24-hour horizon, drops older ones", %{sc: sc} do
    SlidingSum.add(sc, "old", 5)

    Clock.set(200_000)
    SlidingSum.add(sc, "old", 11)

    # now - 86_400_000 == 0: the t=0 bucket sits exactly on the horizon — kept.
    Clock.set(86_400_000)
    send(sc, :cleanup)
    assert 16 == SlidingSum.sum(sc, "old", 100_000_000)

    # 100 s later the t=0 bucket is beyond the horizon and dropped, while the
    # t=200_000 bucket (start 200_000 >= cutoff 100_000) survives.
    Clock.set(86_500_000)
    send(sc, :cleanup)
    assert 11 == SlidingSum.sum(sc, "old", 100_000_000)
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
