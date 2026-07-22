defmodule MonitorTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!({Monitor, []})
    :ok
  end

  # ------------------------------------------------------------------
  # Small mailbox helpers for the timer-based lifecycle test
  # ------------------------------------------------------------------

  defp flush_ticks do
    receive do
      {:tick, _} -> flush_ticks()
    after
      0 -> :ok
    end
  end

  defp collect_ticks(acc) do
    receive do
      {:tick, x} -> collect_ticks([x | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  # ------------------------------------------------------------------
  # Registration basics
  # ------------------------------------------------------------------

  test "a freshly started monitor tracks nothing" do
    assert Monitor.statuses() == %{}
  end

  test "register returns :ok and the service starts :up" do
    assert :ok = Monitor.register("svc", fn -> :ok end, 10_000)
    assert Monitor.status("svc") == :up
    assert Monitor.statuses() == %{"svc" => :up}
  end

  test "register guards a non-positive interval" do
    assert_raise FunctionClauseError, fn ->
      Monitor.register("bad", fn -> :ok end, 0)
    end

    # The server must still be alive and usable afterwards.
    assert :ok = Monitor.register("ok", fn -> :ok end, 10_000)
    assert Monitor.status("ok") == :up
  end

  # ------------------------------------------------------------------
  # Unknown services
  # ------------------------------------------------------------------

  test "status and check_now report unknown services" do
    assert Monitor.status("nope") == {:error, :not_found}
    assert Monitor.check_now("nope") == {:error, :not_found}
  end

  # ------------------------------------------------------------------
  # Status transitions via deterministic check_now
  # ------------------------------------------------------------------

  test "default threshold of 3 consecutive failures marks the service :down" do
    # Long interval so the periodic timer never fires during the test.
    :ok = Monitor.register("svc", fn -> {:error, :x} end, 10_000)

    assert {:ok, :up} = Monitor.check_now("svc")
    assert Monitor.status("svc") == :up

    assert {:ok, :up} = Monitor.check_now("svc")
    assert Monitor.status("svc") == :up

    assert {:ok, :down} = Monitor.check_now("svc")
    assert Monitor.status("svc") == :down
  end

  test "a custom threshold of 1 goes :down on the first failure" do
    :ok = Monitor.register("svc", fn -> {:error, :boom} end, 10_000, threshold: 1)
    assert {:ok, :down} = Monitor.check_now("svc")
    assert Monitor.status("svc") == :down
  end

  test "an :ok result resets the consecutive-failure counter" do
    {:ok, box} = Agent.start_link(fn -> {:error, :e} end)
    check = fn -> Agent.get(box, & &1) end

    :ok = Monitor.register("svc", check, 10_000, threshold: 3)

    # Two failures, then a success resets the counter.
    assert {:ok, :up} = Monitor.check_now("svc")
    assert {:ok, :up} = Monitor.check_now("svc")

    Agent.update(box, fn _ -> :ok end)
    assert {:ok, :up} = Monitor.check_now("svc")

    # Now it takes three fresh failures to go down, not one.
    Agent.update(box, fn _ -> {:error, :e} end)
    assert {:ok, :up} = Monitor.check_now("svc")
    assert {:ok, :up} = Monitor.check_now("svc")
    assert {:ok, :down} = Monitor.check_now("svc")
  end

  # ------------------------------------------------------------------
  # Notification: exactly once per transition
  # ------------------------------------------------------------------

  test "notify fires exactly once on the :up -> :down transition" do
    test = self()

    :ok =
      Monitor.register("svc", fn -> {:error, :boom} end, 10_000,
        threshold: 3,
        notify: fn name, reason -> send(test, {:notified, name, reason}) end
      )

    # No notification before the threshold is reached.
    assert {:ok, :up} = Monitor.check_now("svc")
    assert {:ok, :up} = Monitor.check_now("svc")
    refute_receive {:notified, "svc", _}, 50

    # The third consecutive failure fires the notification once.
    assert {:ok, :down} = Monitor.check_now("svc")
    assert_receive {:notified, "svc", :boom}, 500

    # Further failures while already down must NOT re-notify.
    assert {:ok, :down} = Monitor.check_now("svc")
    assert {:ok, :down} = Monitor.check_now("svc")
    refute_receive {:notified, "svc", _}, 100
  end

  test "recovery then re-failure notifies again (once per distinct transition)" do
    test = self()
    {:ok, box} = Agent.start_link(fn -> {:error, :down1} end)
    check = fn -> Agent.get(box, & &1) end

    :ok =
      Monitor.register("svc", check, 10_000,
        threshold: 2,
        notify: fn name, reason -> send(test, {:notified, name, reason}) end
      )

    # First down transition.
    assert {:ok, :up} = Monitor.check_now("svc")
    assert {:ok, :down} = Monitor.check_now("svc")
    assert_receive {:notified, "svc", :down1}, 500

    # Recover to :up (no notification on recovery).
    Agent.update(box, fn _ -> :ok end)
    assert {:ok, :up} = Monitor.check_now("svc")
    refute_receive {:notified, "svc", _}, 50

    # Fail again -> a fresh down transition fires the notification again.
    Agent.update(box, fn _ -> {:error, :down2} end)
    assert {:ok, :up} = Monitor.check_now("svc")
    assert {:ok, :down} = Monitor.check_now("svc")
    assert_receive {:notified, "svc", :down2}, 500
  end

  # ------------------------------------------------------------------
  # Independence between services
  # ------------------------------------------------------------------

  test "services are independent" do
    :ok = Monitor.register("a", fn -> {:error, :x} end, 10_000, threshold: 1)
    :ok = Monitor.register("b", fn -> :ok end, 10_000, threshold: 1)

    assert {:ok, :down} = Monitor.check_now("a")
    assert {:ok, :up} = Monitor.check_now("b")

    assert Monitor.status("a") == :down
    assert Monitor.status("b") == :up
    assert Monitor.statuses() == %{"a" => :down, "b" => :up}
  end

  # ------------------------------------------------------------------
  # Robustness: unexpected messages are ignored
  # ------------------------------------------------------------------

  test "unexpected messages do not crash the server" do
    :ok = Monitor.register("svc", fn -> :ok end, 10_000)
    send(Monitor, :some_garbage_message)
    send(Monitor, {:more, :garbage})
    # A synchronous call proves the server processed past the garbage intact.
    assert Monitor.status("svc") == :up
  end

  # ------------------------------------------------------------------
  # Periodic scheduling + lifecycle: re-registration kills the old schedule
  # ------------------------------------------------------------------

  test "periodic checks run, and re-registration kills the previous schedule" do
    test = self()

    a = fn ->
      send(test, {:tick, :a})
      :ok
    end

    # First registration: prove the periodic schedule actually runs.
    :ok = Monitor.register("svc", a, 20)
    assert_receive {:tick, :a}, 1_000
    assert_receive {:tick, :a}, 1_000

    # Re-register with a different check function. Because register/4 is a
    # synchronous call, once it returns the new generation is in effect and the
    # old check function can never be invoked again by a leftover timer.
    b = fn ->
      send(test, {:tick, :b})
      :ok
    end

    :ok = Monitor.register("svc", b, 20)

    # Drop any :a ticks queued in our mailbox from before the swap.
    flush_ticks()

    # Over a fresh window we must see the NEW check running and NEVER the old one.
    Process.sleep(200)
    ticks = collect_ticks([])

    assert :b in ticks
    refute :a in ticks
  end
end
