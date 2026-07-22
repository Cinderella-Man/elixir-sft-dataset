defmodule EscalatingWatchdogTest do
  use ExUnit.Case, async: false

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  defp dummy_pid do
    spawn(fn -> Process.sleep(:infinity) end)
  end

  defp warn_notifier(test_pid), do: fn name -> send(test_pid, {:warned, name}) end
  defp timeout_notifier(test_pid), do: fn name -> send(test_pid, {:timed_out, name}) end

  setup do
    start_supervised!({EscalatingWatchdog, []})
    :ok
  end

  # ------------------------------------------------------------------
  # No escalation while heartbeats arrive
  # ------------------------------------------------------------------

  test "neither phase fires while heartbeats arrive within warn_ms" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        80,
        200,
        warn_notifier(test),
        timeout_notifier(test)
      )

    for _ <- 1..4 do
      Process.sleep(40)
      assert :ok = EscalatingWatchdog.heartbeat(:w)
    end

    refute_receive {:warned, :w}, 60
    refute_receive {:timed_out, :w}, 10
  end

  # ------------------------------------------------------------------
  # Two-stage escalation
  # ------------------------------------------------------------------

  test "warn fires first, then timeout" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        60,
        150,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert_receive {:warned, :w}, 1_000
    assert_receive {:timed_out, :w}, 1_000
  end

  test "phase transitions from healthy to warned" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        50,
        10_000,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert {:ok, :healthy} = EscalatingWatchdog.phase(:w)
    assert_receive {:warned, :w}, 1_000
    assert {:ok, :warned} = EscalatingWatchdog.phase(:w)
  end

  test "callbacks receive the registered name" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        {:svc, 9},
        dummy_pid(),
        40,
        90,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert_receive {:warned, {:svc, 9}}, 1_000
    assert_receive {:timed_out, {:svc, 9}}, 1_000
  end

  # ------------------------------------------------------------------
  # Heartbeat resets escalation
  # ------------------------------------------------------------------

  test "heartbeat before warn prevents the warning in that window" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        80,
        400,
        warn_notifier(test),
        timeout_notifier(test)
      )

    Process.sleep(40)
    assert :ok = EscalatingWatchdog.heartbeat(:w)

    refute_receive {:warned, :w}, 60
  end

  test "heartbeat after warn re-arms so the warning can fire again and the timeout is deferred" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        50,
        250,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert_receive {:warned, :w}, 1_000
    assert :ok = EscalatingWatchdog.heartbeat(:w)
    assert {:ok, :healthy} = EscalatingWatchdog.phase(:w)

    # The warning re-arms and fires again from the fresh clock...
    assert_receive {:warned, :w}, 1_000
    # ...and the timeout has not fired because the clock was reset.
    refute_receive {:timed_out, :w}, 10

    assert :ok = EscalatingWatchdog.unregister(:w)
  end

  # ------------------------------------------------------------------
  # One-shot timeout removes the registration
  # ------------------------------------------------------------------

  test "timeout removes the registration and does not fire again" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        40,
        90,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert_receive {:timed_out, :w}, 1_000
    assert {:error, :not_registered} = EscalatingWatchdog.phase(:w)
    refute_receive {:timed_out, :w}, 200
  end

  # ------------------------------------------------------------------
  # Independence and unregister
  # ------------------------------------------------------------------

  test "registrations are independent" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :fast,
        dummy_pid(),
        40,
        90,
        warn_notifier(test),
        timeout_notifier(test)
      )

    :ok =
      EscalatingWatchdog.register(
        :slow,
        dummy_pid(),
        5_000,
        10_000,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert_receive {:timed_out, :fast}, 1_000
    refute_receive {:warned, :slow}, 50
  end

  test "unregister prevents both callbacks" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        40,
        90,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert :ok = EscalatingWatchdog.unregister(:w)

    refute_receive {:warned, :w}, 200
    refute_receive {:timed_out, :w}, 100
  end

  # ------------------------------------------------------------------
  # Validation and unknown-name behaviour
  # ------------------------------------------------------------------

  test "register raises when warn_ms is not strictly less than timeout_ms" do
    test = self()

    assert_raise ArgumentError, fn ->
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        100,
        100,
        warn_notifier(test),
        timeout_notifier(test)
      )
    end

    assert_raise ArgumentError, fn ->
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        200,
        100,
        warn_notifier(test),
        timeout_notifier(test)
      )
    end
  end

  test "phase and heartbeat for unknown names" do
    assert {:error, :not_registered} = EscalatingWatchdog.phase(:nope)
    assert :ok = EscalatingWatchdog.heartbeat(:nope)
  end

  # ------------------------------------------------------------------
  # Custom :name option
  # ------------------------------------------------------------------

  test "start_link accepts a :name option" do
    {:ok, pid} = EscalatingWatchdog.start_link(name: :custom_escalating)
    assert is_pid(pid)
    assert Process.whereis(:custom_escalating) == pid
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
  end

  test "re-registering with longer deadlines defers past the old deadlines" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        40,
        90,
        warn_notifier(test),
        timeout_notifier(test)
      )

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        5_000,
        10_000,
        warn_notifier(test),
        timeout_notifier(test)
      )

    # The replaced 40/90 deadlines must be dead: drive real time well past both.
    refute_receive {:warned, :w}, 250
    refute_receive {:timed_out, :w}, 10
    assert {:ok, :healthy} = EscalatingWatchdog.phase(:w)
    assert :ok = EscalatingWatchdog.unregister(:w)
  end

  test "heartbeat after the warning defers the timeout past its original deadline" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        50,
        200,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert_receive {:warned, :w}, 1_000
    assert :ok = EscalatingWatchdog.heartbeat(:w)

    # The original timeout deadline (~200ms from registration) must pass silently.
    refute_receive {:timed_out, :w}, 180
    assert :ok = EscalatingWatchdog.unregister(:w)
  end

  test "unregister after the warning prevents the pending timeout" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        40,
        200,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert_receive {:warned, :w}, 1_000
    assert :ok = EscalatingWatchdog.unregister(:w)
    assert {:error, :not_registered} = EscalatingWatchdog.phase(:w)

    refute_receive {:timed_out, :w}, 300
  end

  test "the warning fires only once while the entity stays silent" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        40,
        5_000,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert_receive {:warned, :w}, 1_000
    refute_receive {:warned, :w}, 250
    assert {:ok, :warned} = EscalatingWatchdog.phase(:w)
    assert :ok = EscalatingWatchdog.unregister(:w)
  end
end
