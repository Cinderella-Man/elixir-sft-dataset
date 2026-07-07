defmodule MaxWaitDebouncerTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(MaxWaitDebouncer)
    :ok
  end

  defp notify(tag) do
    test = self()
    fn -> send(test, tag) end
  end

  # -------------------------------------------------------
  # Basic coalescing + delay
  # -------------------------------------------------------

  test "coalesces to the last func after the delay when the burst settles" do
    MaxWaitDebouncer.call("k", 150, 1000, notify({:ran, 1}))
    MaxWaitDebouncer.call("k", 150, 1000, notify({:ran, 2}))
    MaxWaitDebouncer.call("k", 150, 1000, notify({:ran, 3}))

    assert_receive {:ran, 3}, 600
    refute_received {:ran, 1}
    refute_received {:ran, 2}
  end

  test "does not run before the delay elapses" do
    MaxWaitDebouncer.call("k", 200, 1000, notify(:done))
    refute_receive :done, 120
    assert_receive :done, 400
  end

  # -------------------------------------------------------
  # Max-wait guarantee
  # -------------------------------------------------------

  test "fires by max_ms even though the delay timer keeps resetting" do
    # delay=150, max=250. A plain debouncer would keep pushing the fire to
    # ~last_call + 150; the max-wait bound forces a fire at ~first_call + 250.
    MaxWaitDebouncer.call("k", 150, 250, notify(:fired))
    Process.sleep(100)
    # t=100: resets delay timer (would fire at ~250 anyway)
    MaxWaitDebouncer.call("k", 150, 250, notify(:fired))
    Process.sleep(100)
    # t=200: delay would push fire to ~350, but max deadline is ~250.
    MaxWaitDebouncer.call("k", 150, 250, notify(:fired))

    # From here (~t=200) the max deadline (~250) is only ~50ms away, well before
    # the ~350 the delay timer would give.
    assert_receive :fired, 175
  end

  test "single call within max simply obeys the normal delay" do
    MaxWaitDebouncer.call("k", 100, 1000, notify(:one))
    assert_receive :one, 400
    refute_receive :one, 200
  end

  # -------------------------------------------------------
  # flush / cancel
  # -------------------------------------------------------

  test "flush runs the pending func immediately" do
    MaxWaitDebouncer.call("k", 500, 5000, notify(:flushed))
    assert :ok = MaxWaitDebouncer.flush("k")

    # Runs well before the 500ms delay would have.
    assert_receive :flushed, 200
    # And does not run a second time.
    refute_receive :flushed, 600
  end

  test "flush with nothing pending is a no-op returning :ok" do
    assert :ok = MaxWaitDebouncer.flush("absent")
    refute_receive _, 100
  end

  test "cancel discards the pending func" do
    MaxWaitDebouncer.call("k", 200, 1000, notify(:cancelled))
    assert :ok = MaxWaitDebouncer.cancel("k")

    refute_receive :cancelled, 400
  end

  # -------------------------------------------------------
  # Independence + fresh bursts + contract
  # -------------------------------------------------------

  test "different keys are independent" do
    MaxWaitDebouncer.call("a", 100, 1000, notify({:key, "a"}))
    MaxWaitDebouncer.call("b", 100, 1000, notify({:key, "b"}))

    assert_receive {:key, "a"}, 400
    assert_receive {:key, "b"}, 400
  end

  test "a fresh call after firing starts a new max-wait window" do
    MaxWaitDebouncer.call("k", 100, 1000, notify(:first))
    assert_receive :first, 400

    MaxWaitDebouncer.call("k", 100, 1000, notify(:second))
    assert_receive :second, 400
  end

  test "call/4 returns :ok promptly even with a blocking func" do
    slow = fn -> Process.sleep(300) end
    {micros, :ok} = :timer.tc(fn -> MaxWaitDebouncer.call("s", 50, 500, slow) end)
    assert micros < 100_000
  end
end
