defmodule WatchdogTest do
  use ExUnit.Case, async: false

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  # A dummy long-lived process to pass as the monitored pid.
  defp dummy_pid do
    spawn(fn -> Process.sleep(:infinity) end)
  end

  # Build a callback that reports timeouts to the current test process.
  # Tagged so different registrations can be told apart.
  defp notifier(test_pid, tag \\ :timed_out) do
    fn name -> send(test_pid, {tag, name}) end
  end

  setup do
    start_supervised!({Watchdog, []})
    :ok
  end

  # ------------------------------------------------------------------
  # No timeout while heartbeats arrive on time
  # ------------------------------------------------------------------

  test "does not fire while heartbeats arrive within the interval" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 120, notifier(test))

    # Heartbeat every 40ms, well under the 120ms interval.
    for _ <- 1..4 do
      Process.sleep(40)
      assert :ok = Watchdog.heartbeat(:worker)
    end

    # After the last heartbeat, less than one interval has elapsed.
    refute_receive {:timed_out, :worker}, 60
  end

  # ------------------------------------------------------------------
  # Timeout fires when heartbeats stop
  # ------------------------------------------------------------------

  test "fires the callback when a heartbeat is missed" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 60, notifier(test))

    # Never heartbeat -> timeout must fire.
    assert_receive {:timed_out, :worker}, 1_000
  end

  test "callback receives the registered name" do
    test = self()
    :ok = Watchdog.register({:svc, 42}, dummy_pid(), 50, notifier(test))

    assert_receive {:timed_out, {:svc, 42}}, 1_000
  end

  # ------------------------------------------------------------------
  # Heartbeat resets the timer
  # ------------------------------------------------------------------

  test "heartbeat resets the timer so cumulative uptime exceeds the interval" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 90, notifier(test))

    # Two heartbeats spaced 60ms apart: total 120ms > 90ms interval,
    # but each heartbeat resets the clock so no timeout should occur yet.
    Process.sleep(60)
    assert :ok = Watchdog.heartbeat(:worker)
    Process.sleep(60)
    assert :ok = Watchdog.heartbeat(:worker)

    refute_receive {:timed_out, :worker}, 40

    # Now stop heartbeating; the timer should eventually fire.
    assert_receive {:timed_out, :worker}, 1_000
  end

  # ------------------------------------------------------------------
  # Unregister prevents the callback
  # ------------------------------------------------------------------

  test "unregister prevents the callback from firing" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 60, notifier(test))
    assert :ok = Watchdog.unregister(:worker)

    refute_receive {:timed_out, :worker}, 300
  end

  test "unregistering an unknown name is a harmless no-op" do
    assert :ok = Watchdog.unregister(:never_registered)
  end

  test "heartbeat for an unknown name is a harmless no-op" do
    assert :ok = Watchdog.heartbeat(:never_registered)
  end

  # ------------------------------------------------------------------
  # One-shot semantics
  # ------------------------------------------------------------------

  test "timeout fires exactly once then stops" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 50, notifier(test))

    assert_receive {:timed_out, :worker}, 1_000
    # Must not fire again for the same (now removed) registration.
    refute_receive {:timed_out, :worker}, 300
  end

  test "heartbeat after a timeout is a no-op (registration already removed)" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 50, notifier(test))

    assert_receive {:timed_out, :worker}, 1_000

    # The registration is gone; heartbeating must not re-arm anything.
    assert :ok = Watchdog.heartbeat(:worker)
    refute_receive {:timed_out, :worker}, 300
  end

  # ------------------------------------------------------------------
  # Independence between registrations
  # ------------------------------------------------------------------

  test "registrations are independent" do
    test = self()
    :ok = Watchdog.register(:fast, dummy_pid(), 60, notifier(test))
    :ok = Watchdog.register(:slow, dummy_pid(), 10_000, notifier(test))

    assert_receive {:timed_out, :fast}, 1_000
    # The slow one must not have fired.
    refute_receive {:timed_out, :slow}, 100
  end

  test "unregistering one name does not affect another" do
    test = self()
    :ok = Watchdog.register(:keep, dummy_pid(), 60, notifier(test))
    :ok = Watchdog.register(:drop, dummy_pid(), 60, notifier(test))

    assert :ok = Watchdog.unregister(:drop)

    assert_receive {:timed_out, :keep}, 1_000
    refute_receive {:timed_out, :drop}, 100
  end

  # ------------------------------------------------------------------
  # Re-registration replaces the previous registration
  # ------------------------------------------------------------------

  test "re-registering a name replaces interval and callback" do
    test = self()

    # First registration: long interval, tag :old.
    :ok = Watchdog.register(:worker, dummy_pid(), 10_000, notifier(test, :old))

    # Replace with a short interval and a different callback tag.
    :ok = Watchdog.register(:worker, dummy_pid(), 60, notifier(test, :new))

    # The new (short) registration must fire...
    assert_receive {:new, :worker}, 1_000
    # ...and the old callback must never fire.
    refute_receive {:old, :worker}, 100
  end

  test "re-registering re-arms the timer with a fresh clock" do
    test = self()

    :ok = Watchdog.register(:worker, dummy_pid(), 200, notifier(test))
    Process.sleep(120)
    # Re-register before the first interval elapses; clock restarts.
    :ok = Watchdog.register(:worker, dummy_pid(), 200, notifier(test))

    # 120ms after re-registration is still under the 200ms interval.
    refute_receive {:timed_out, :worker}, 120

    # Eventually it should fire from the fresh registration.
    assert_receive {:timed_out, :worker}, 1_000
  end

  # ------------------------------------------------------------------
  # Custom :name option
  # ------------------------------------------------------------------

  test "start_link accepts a :name option" do
    {:ok, pid} = Watchdog.start_link(name: :custom_watchdog)
    assert is_pid(pid)
    assert Process.whereis(:custom_watchdog) == pid
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
  end
end
