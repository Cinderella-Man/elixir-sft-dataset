defmodule GraceWatchdogTest do
  use ExUnit.Case, async: false

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  defp dummy_pid do
    spawn(fn -> Process.sleep(:infinity) end)
  end

  defp notifier(test_pid, tag \\ :timed_out) do
    fn name, misses -> send(test_pid, {tag, name, misses}) end
  end

  setup do
    start_supervised!({GraceWatchdog, []})
    :ok
  end

  # ------------------------------------------------------------------
  # No timeout while heartbeats arrive
  # ------------------------------------------------------------------

  test "does not fire while heartbeats arrive within the interval" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 80, 2, notifier(test))

    for _ <- 1..4 do
      Process.sleep(40)
      assert :ok = GraceWatchdog.heartbeat(:w)
    end

    refute_receive {:timed_out, :w, _}, 60
  end

  # ------------------------------------------------------------------
  # Threshold behaviour
  # ------------------------------------------------------------------

  test "fires only after max_misses consecutive missed intervals" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 50, 3, notifier(test))

    # With interval 50 and threshold 3, the earliest fire is ~150ms.
    refute_receive {:timed_out, :w, _}, 100
    assert_receive {:timed_out, :w, 3}, 1_000
  end

  test "max_misses of 1 fires after a single missed interval" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 50, 1, notifier(test))

    assert_receive {:timed_out, :w, 1}, 1_000
  end

  test "callback receives the name and the miss count" do
    test = self()
    :ok = GraceWatchdog.register({:svc, 1}, dummy_pid(), 40, 2, notifier(test))

    assert_receive {:timed_out, {:svc, 1}, 2}, 1_000
  end

  # ------------------------------------------------------------------
  # Miss counter accumulation and reset
  # ------------------------------------------------------------------

  test "misses accumulate over intervals and are queryable" do
    :ok = GraceWatchdog.register(:w, dummy_pid(), 80, 5, notifier(self()))

    # One interval elapses (~80ms); at 120ms exactly one miss recorded.
    Process.sleep(120)
    assert {:ok, 1} = GraceWatchdog.misses(:w)
  end

  test "a heartbeat resets the accumulated miss count" do
    :ok = GraceWatchdog.register(:w, dummy_pid(), 80, 5, notifier(self()))

    Process.sleep(120)
    assert {:ok, 1} = GraceWatchdog.misses(:w)
    assert :ok = GraceWatchdog.heartbeat(:w)
    assert {:ok, 0} = GraceWatchdog.misses(:w)
  end

  test "misses for an unknown name returns an error" do
    assert {:error, :not_registered} = GraceWatchdog.misses(:nope)
  end

  test "steady heartbeats keep the miss count at zero so it never fires" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 60, 2, notifier(test))

    for _ <- 1..5 do
      Process.sleep(30)
      assert :ok = GraceWatchdog.heartbeat(:w)
    end

    refute_receive {:timed_out, :w, _}, 40
  end

  # ------------------------------------------------------------------
  # One-shot semantics
  # ------------------------------------------------------------------

  test "fires exactly once then stops" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 40, 2, notifier(test))

    assert_receive {:timed_out, :w, 2}, 1_000
    refute_receive {:timed_out, :w, _}, 200
  end

  # ------------------------------------------------------------------
  # Independence and replacement
  # ------------------------------------------------------------------

  test "registrations are independent" do
    test = self()
    :ok = GraceWatchdog.register(:fast, dummy_pid(), 40, 2, notifier(test))
    :ok = GraceWatchdog.register(:slow, dummy_pid(), 10_000, 2, notifier(test))

    assert_receive {:timed_out, :fast, 2}, 1_000
    refute_receive {:timed_out, :slow, _}, 100
  end

  test "re-registering replaces interval, threshold and callback" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 10_000, 5, notifier(test, :old))
    :ok = GraceWatchdog.register(:w, dummy_pid(), 40, 1, notifier(test, :new))

    assert_receive {:new, :w, 1}, 1_000
    refute_receive {:old, :w, _}, 100
  end

  # ------------------------------------------------------------------
  # Unregister and unknown-name no-ops
  # ------------------------------------------------------------------

  test "unregister prevents the callback from firing" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 40, 2, notifier(test))
    assert :ok = GraceWatchdog.unregister(:w)

    refute_receive {:timed_out, :w, _}, 300
  end

  test "heartbeat for an unknown name is a harmless no-op" do
    assert :ok = GraceWatchdog.heartbeat(:nope)
  end

  # ------------------------------------------------------------------
  # Custom :name option
  # ------------------------------------------------------------------

  test "start_link accepts a :name option" do
    {:ok, pid} = GraceWatchdog.start_link(name: :custom_grace)
    assert is_pid(pid)
    assert Process.whereis(:custom_grace) == pid
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
  end
end