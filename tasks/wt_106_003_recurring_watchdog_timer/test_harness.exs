defmodule RecurringWatchdogTest do
  use ExUnit.Case, async: false

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  defp dummy_pid do
    spawn(fn -> Process.sleep(:infinity) end)
  end

  defp notifier(test_pid, tag \\ :alert) do
    fn name -> send(test_pid, {tag, name}) end
  end

  setup do
    start_supervised!({RecurringWatchdog, []})
    :ok
  end

  # ------------------------------------------------------------------
  # Healthy while heartbeats arrive
  # ------------------------------------------------------------------

  test "stays healthy while heartbeats arrive within the interval" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 100, notifier(test))

    for _ <- 1..4 do
      Process.sleep(40)
      assert :ok = RecurringWatchdog.heartbeat(:w)
    end

    refute_receive {:alert, :w}, 60
    assert {:ok, :healthy} = RecurringWatchdog.status(:w)
  end

  # ------------------------------------------------------------------
  # Recurring alerts
  # ------------------------------------------------------------------

  test "fires repeatedly while heartbeats are missing" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 50, notifier(test))

    assert_receive {:alert, :w}, 1_000
    assert_receive {:alert, :w}, 1_000
    assert_receive {:alert, :w}, 1_000
  end

  test "status becomes alerting after the first miss and healthy again after a heartbeat" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 50, notifier(test))

    assert_receive {:alert, :w}, 1_000
    assert {:ok, :alerting} = RecurringWatchdog.status(:w)

    assert :ok = RecurringWatchdog.heartbeat(:w)
    assert {:ok, :healthy} = RecurringWatchdog.status(:w)
  end

  test "resumed heartbeats silence the recurring alerts" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 60, notifier(test))

    assert_receive {:alert, :w}, 1_000

    # Heartbeat steadily, faster than the interval.
    for _ <- 1..5 do
      Process.sleep(30)
      assert :ok = RecurringWatchdog.heartbeat(:w)
    end

    refute_receive {:alert, :w}, 40
    assert {:ok, :healthy} = RecurringWatchdog.status(:w)
  end

  test "callback receives the registered name" do
    test = self()
    :ok = RecurringWatchdog.register({:svc, 7}, dummy_pid(), 50, notifier(test))

    assert_receive {:alert, {:svc, 7}}, 1_000
  end

  # ------------------------------------------------------------------
  # Independence, replacement, unregister
  # ------------------------------------------------------------------

  test "registrations are independent" do
    test = self()
    :ok = RecurringWatchdog.register(:fast, dummy_pid(), 50, notifier(test))
    :ok = RecurringWatchdog.register(:slow, dummy_pid(), 10_000, notifier(test))

    assert_receive {:alert, :fast}, 1_000
    refute_receive {:alert, :slow}, 100
  end

  test "unregister stops the recurring alerts" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 50, notifier(test))

    assert_receive {:alert, :w}, 1_000
    assert :ok = RecurringWatchdog.unregister(:w)

    refute_receive {:alert, :w}, 300
    assert {:error, :not_registered} = RecurringWatchdog.status(:w)
  end

  test "re-registering replaces the previous registration" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 10_000, notifier(test, :old))
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 50, notifier(test, :new))

    assert_receive {:new, :w}, 1_000
    refute_receive {:old, :w}, 100
  end

  test "heartbeat and status for unknown names" do
    assert :ok = RecurringWatchdog.heartbeat(:nope)
    assert {:error, :not_registered} = RecurringWatchdog.status(:nope)
  end

  # ------------------------------------------------------------------
  # Custom :name option
  # ------------------------------------------------------------------

  test "start_link accepts a :name option" do
    {:ok, pid} = RecurringWatchdog.start_link(name: :custom_recurring)
    assert is_pid(pid)
    assert Process.whereis(:custom_recurring) == pid
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
  end
end
