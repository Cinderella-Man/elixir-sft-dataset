defmodule BatchDebouncerTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(BatchDebouncer)
    :ok
  end

  # Handler that reports the batch it received, tagged so we can tell handlers apart.
  defp report(tag) do
    test = self()
    fn batch -> send(test, {tag, batch}) end
  end

  # -------------------------------------------------------
  # Accumulation + ordering
  # -------------------------------------------------------

  test "accumulates all items in a burst and flushes them once, in order" do
    BatchDebouncer.call("k", 150, :a, report(:batch))
    BatchDebouncer.call("k", 150, :b, report(:batch))
    BatchDebouncer.call("k", 150, :c, report(:batch))

    assert_receive {:batch, [:a, :b, :c]}, 600
    # Only one flush for the burst.
    refute_receive {:batch, _}, 250
  end

  test "the most recently supplied handler receives the full batch" do
    BatchDebouncer.call("k", 150, 1, report(:h1))
    BatchDebouncer.call("k", 150, 2, report(:h2))
    BatchDebouncer.call("k", 150, 3, report(:h3))

    # h3 is the latest handler; it gets the whole ordered batch.
    assert_receive {:h3, [1, 2, 3]}, 600
    refute_received {:h1, _}
    refute_received {:h2, _}
  end

  # -------------------------------------------------------
  # Delay respected
  # -------------------------------------------------------

  test "does not flush before the delay elapses" do
    BatchDebouncer.call("k", 200, :x, report(:batch))
    refute_receive {:batch, _}, 120
    assert_receive {:batch, [:x]}, 400
  end

  test "each call resets the timer" do
    BatchDebouncer.call("k", 200, :first, report(:batch))
    Process.sleep(100)
    BatchDebouncer.call("k", 200, :second, report(:batch))

    # First item's timer (t=200) must not have fired — it was reset at t=100.
    refute_receive {:batch, _}, 150
    assert_receive {:batch, [:first, :second]}, 500
  end

  # -------------------------------------------------------
  # pending/1
  # -------------------------------------------------------

  test "pending reflects the buffer size and resets after flush" do
    assert BatchDebouncer.pending("k") == 0

    BatchDebouncer.call("k", 300, :a, report(:batch))
    BatchDebouncer.call("k", 300, :b, report(:batch))
    assert BatchDebouncer.pending("k") == 2

    assert_receive {:batch, [:a, :b]}, 600
    assert BatchDebouncer.pending("k") == 0
  end

  # -------------------------------------------------------
  # Independence + fresh batches
  # -------------------------------------------------------

  test "different keys accumulate independent batches" do
    BatchDebouncer.call("a", 150, :a1, report(:batch))
    BatchDebouncer.call("a", 150, :a2, report(:batch))
    BatchDebouncer.call("b", 150, :b1, report(:batch))

    assert_receive {:batch, [:a1, :a2]}, 500
    assert_receive {:batch, [:b1]}, 500
  end

  test "a call after a flush starts a brand-new batch" do
    BatchDebouncer.call("k", 100, :one, report(:batch))
    assert_receive {:batch, [:one]}, 400

    BatchDebouncer.call("k", 100, :two, report(:batch))
    assert_receive {:batch, [:two]}, 400
  end

  # -------------------------------------------------------
  # Contract
  # -------------------------------------------------------

  test "call/4 returns :ok promptly even when the handler would block" do
    slow = fn _batch -> Process.sleep(300) end
    {micros, :ok} = :timer.tc(fn -> BatchDebouncer.call("s", 50, :item, slow) end)
    assert micros < 100_000
  end
end