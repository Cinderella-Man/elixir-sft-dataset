defmodule ManagedMonitorTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  # --- Notification collector ---

  defmodule Notifications do
    use Agent

    def start_link(_) do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def record(service, event, detail) do
      Agent.update(__MODULE__, &[{service, event, detail} | &1])
    end

    def all, do: Agent.get(__MODULE__, &Enum.reverse/1)
    def count, do: Agent.get(__MODULE__, &length/1)

    def count_event(event) do
      Agent.get(__MODULE__, fn entries ->
        Enum.count(entries, fn {_, e, _} -> e == event end)
      end)
    end

    def clear, do: Agent.update(__MODULE__, fn _ -> [] end)
  end

  # --- Controllable check function ---

  defmodule CheckFn do
    use Agent

    def start_link(_) do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    def set_result(service, result) do
      Agent.update(__MODULE__, &Map.put(&1, service, result))
    end

    def build(service) do
      fn -> Agent.get(__MODULE__, &Map.get(&1, service, :ok)) end
    end
  end

  setup do
    start_supervised!({Clock, 0})
    start_supervised!(Notifications)
    start_supervised!(CheckFn)

    {:ok, pid} =
      ManagedMonitor.start_link(
        clock: &Clock.now/0,
        notify: &Notifications.record/3
      )

    %{mon: pid}
  end

  defp trigger_check(mon, service_name) do
    send(mon, {:check, service_name})
    _ = ManagedMonitor.status(mon, service_name)
  end

  # -------------------------------------------------------
  # Registration
  # -------------------------------------------------------

  test "newly registered service starts in :pending status", %{mon: mon} do
    check = CheckFn.build("web")
    assert :ok = ManagedMonitor.register(mon, "web", check, 5_000)

    assert {:ok, info} = ManagedMonitor.status(mon, "web")
    assert info.status == :pending
    assert info.consecutive_failures == 0
    assert info.last_check_at == nil
    assert info.maintenance_ends_at == nil
  end

  test "cannot register the same service name twice", %{mon: mon} do
    check = CheckFn.build("web")
    assert :ok = ManagedMonitor.register(mon, "web", check, 5_000)
    assert {:error, :already_registered} = ManagedMonitor.register(mon, "web", check, 5_000)
  end

  test "status returns :not_found for unregistered service", %{mon: mon} do
    assert {:error, :not_found} = ManagedMonitor.status(mon, "ghost")
  end

  # -------------------------------------------------------
  # Successful checks → :up
  # -------------------------------------------------------

  test "service becomes :up after a successful check", %{mon: mon} do
    CheckFn.set_result("web", :ok)
    check = CheckFn.build("web")
    ManagedMonitor.register(mon, "web", check, 5_000)

    Clock.advance(5_000)
    trigger_check(mon, "web")

    assert {:ok, info} = ManagedMonitor.status(mon, "web")
    assert info.status == :up
    assert info.consecutive_failures == 0
    assert info.last_check_at == 5_000
  end

  # -------------------------------------------------------
  # Failures and :down transition
  # -------------------------------------------------------

  test "service goes :down after max_failures consecutive failures", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    ManagedMonitor.register(mon, "db", check, 1_000)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    assert {:ok, %{status: :down, consecutive_failures: 3}} =
             ManagedMonitor.status(mon, "db")
  end

  test "notification fires exactly once on transition to :down", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    ManagedMonitor.register(mon, "db", check, 1_000)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    assert Notifications.count_event(:down) == 1

    # A 4th failure should NOT trigger another notification
    Clock.advance(1_000)
    trigger_check(mon, "db")

    assert Notifications.count_event(:down) == 1
  end

  # -------------------------------------------------------
  # Recovery from :down → :up
  # -------------------------------------------------------

  test "a :down service recovers to :up when check succeeds", %{mon: mon} do
    CheckFn.set_result("api", {:error, :crash})
    check = CheckFn.build("api")
    ManagedMonitor.register(mon, "api", check, 1_000)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert {:ok, %{status: :down}} = ManagedMonitor.status(mon, "api")

    CheckFn.set_result("api", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "api")

    assert {:ok, %{status: :up, consecutive_failures: 0}} =
             ManagedMonitor.status(mon, "api")
  end

  test "recovery notification fires when service goes from :down to :up", %{mon: mon} do
    CheckFn.set_result("api", {:error, :crash})
    check = CheckFn.build("api")
    ManagedMonitor.register(mon, "api", check, 1_000)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    CheckFn.set_result("api", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "api")

    assert Notifications.count_event(:recovered) == 1

    recovery_events =
      Notifications.all()
      |> Enum.filter(fn {_, event, _} -> event == :recovered end)

    assert [{"api", :recovered, nil}] = recovery_events
  end

  test "notification fires again if service goes down a second time after recovery", %{mon: mon} do
    CheckFn.set_result("api", {:error, :crash})
    check = CheckFn.build("api")
    ManagedMonitor.register(mon, "api", check, 1_000)

    # First down
    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    # Recover
    CheckFn.set_result("api", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "api")

    # Second down
    CheckFn.set_result("api", {:error, :oom})

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert Notifications.count_event(:down) == 2

    down_events =
      Notifications.all()
      |> Enum.filter(fn {_, event, _} -> event == :down end)

    assert [{"api", :down, :crash}, {"api", :down, :oom}] = down_events
  end

  # -------------------------------------------------------
  # Pause / Resume
  # -------------------------------------------------------

  test "pausing a service changes its reported status to :paused", %{mon: mon} do
    CheckFn.set_result("web", :ok)
    check = CheckFn.build("web")
    ManagedMonitor.register(mon, "web", check, 1_000)

    # Get to :up first
    Clock.advance(1_000)
    trigger_check(mon, "web")
    assert {:ok, %{status: :up}} = ManagedMonitor.status(mon, "web")

    assert :ok = ManagedMonitor.pause(mon, "web")
    assert {:ok, %{status: :paused}} = ManagedMonitor.status(mon, "web")
  end

  test "checks are skipped while paused", %{mon: mon} do
    CheckFn.set_result("web", {:error, :fail})
    check = CheckFn.build("web")
    ManagedMonitor.register(mon, "web", check, 1_000)

    # Get to :up first with a success
    CheckFn.set_result("web", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "web")

    ManagedMonitor.pause(mon, "web")

    # Now set to failing and trigger checks
    CheckFn.set_result("web", {:error, :fail})

    for _ <- 1..5 do
      Clock.advance(1_000)
      trigger_check(mon, "web")
    end

    # Failures should NOT have been counted
    assert {:ok, %{consecutive_failures: 0}} = ManagedMonitor.status(mon, "web")
  end

  test "resuming restores the pre-pause health status", %{mon: mon} do
    CheckFn.set_result("web", :ok)
    check = CheckFn.build("web")
    ManagedMonitor.register(mon, "web", check, 1_000)

    Clock.advance(1_000)
    trigger_check(mon, "web")
    assert {:ok, %{status: :up}} = ManagedMonitor.status(mon, "web")

    ManagedMonitor.pause(mon, "web")
    assert {:ok, %{status: :paused}} = ManagedMonitor.status(mon, "web")

    ManagedMonitor.resume(mon, "web")
    assert {:ok, %{status: :up}} = ManagedMonitor.status(mon, "web")
  end

  test "resume returns :not_paused for active services", %{mon: mon} do
    CheckFn.set_result("web", :ok)
    check = CheckFn.build("web")
    ManagedMonitor.register(mon, "web", check, 1_000)

    assert {:error, :not_paused} = ManagedMonitor.resume(mon, "web")
  end

  test "pause returns :not_found for unknown service", %{mon: mon} do
    assert {:error, :not_found} = ManagedMonitor.pause(mon, "ghost")
  end

  # -------------------------------------------------------
  # Maintenance mode
  # -------------------------------------------------------

  test "maintenance mode reports :maintenance status", %{mon: mon} do
    CheckFn.set_result("db", :ok)
    check = CheckFn.build("db")
    ManagedMonitor.register(mon, "db", check, 1_000)

    Clock.advance(1_000)
    trigger_check(mon, "db")

    assert :ok = ManagedMonitor.maintenance(mon, "db", 10_000)
    assert {:ok, info} = ManagedMonitor.status(mon, "db")
    assert info.status == :maintenance
    assert info.maintenance_ends_at == 11_000
  end

  test "failures during maintenance do not increment the counter", %{mon: mon} do
    CheckFn.set_result("db", :ok)
    check = CheckFn.build("db")
    ManagedMonitor.register(mon, "db", check, 1_000)

    Clock.advance(1_000)
    trigger_check(mon, "db")

    ManagedMonitor.maintenance(mon, "db", 60_000)

    CheckFn.set_result("db", {:error, :timeout})

    for _ <- 1..5 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    assert {:ok, %{consecutive_failures: 0}} = ManagedMonitor.status(mon, "db")
    assert Notifications.count_event(:down) == 0
  end

  test "successes during maintenance still update health to :up", %{mon: mon} do
    CheckFn.set_result("db", {:error, :crash})
    check = CheckFn.build("db")
    ManagedMonitor.register(mon, "db", check, 1_000)

    # Drive to :down
    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    # Enter maintenance and succeed
    ManagedMonitor.maintenance(mon, "db", 60_000)
    CheckFn.set_result("db", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "db")

    # Still shows :maintenance, but internal health is :up
    assert {:ok, %{status: :maintenance, consecutive_failures: 0}} =
             ManagedMonitor.status(mon, "db")
  end

  test "maintenance_started notification fires", %{mon: mon} do
    check = CheckFn.build("db")
    ManagedMonitor.register(mon, "db", check, 1_000)

    ManagedMonitor.maintenance(mon, "db", 10_000)

    maint_events =
      Notifications.all()
      |> Enum.filter(fn {_, event, _} -> event == :maintenance_started end)

    assert [{"db", :maintenance_started, 10_000}] = maint_events
  end

  test "maintenance auto-expires and restores health status", %{mon: mon} do
    CheckFn.set_result("db", :ok)
    check = CheckFn.build("db")
    ManagedMonitor.register(mon, "db", check, 1_000)

    Clock.advance(1_000)
    trigger_check(mon, "db")

    ManagedMonitor.maintenance(mon, "db", 5_000)
    assert {:ok, %{status: :maintenance}} = ManagedMonitor.status(mon, "db")

    # Simulate the maintenance_end timer firing
    send(mon, {:maintenance_end, "db"})
    _ = ManagedMonitor.status(mon, "db")

    assert {:ok, %{status: :up}} = ManagedMonitor.status(mon, "db")

    assert Notifications.count_event(:maintenance_ended) == 1
  end

  test "maintenance can be resumed manually before expiry", %{mon: mon} do
    check = CheckFn.build("db")
    ManagedMonitor.register(mon, "db", check, 1_000)

    ManagedMonitor.maintenance(mon, "db", 60_000)
    assert {:ok, %{status: :maintenance}} = ManagedMonitor.status(mon, "db")

    ManagedMonitor.resume(mon, "db")
    assert {:ok, %{status: :pending}} = ManagedMonitor.status(mon, "db")

    # Stale maintenance_end should be discarded
    send(mon, {:maintenance_end, "db"})
    _ = ManagedMonitor.status(mon, "db")

    # Should still be pending (not re-transitioned)
    assert {:ok, %{status: :pending}} = ManagedMonitor.status(mon, "db")
    assert Notifications.count_event(:maintenance_ended) == 0
  end

  test "re-entering maintenance replaces the duration", %{mon: mon} do
    check = CheckFn.build("db")
    ManagedMonitor.register(mon, "db", check, 1_000)

    ManagedMonitor.maintenance(mon, "db", 5_000)
    assert {:ok, %{maintenance_ends_at: 5_000}} = ManagedMonitor.status(mon, "db")

    Clock.advance(2_000)
    ManagedMonitor.maintenance(mon, "db", 10_000)
    assert {:ok, %{maintenance_ends_at: 12_000}} = ManagedMonitor.status(mon, "db")

    assert Notifications.count_event(:maintenance_started) == 2
  end

  # -------------------------------------------------------
  # Deregistration
  # -------------------------------------------------------

  test "deregistering a service removes it from statuses", %{mon: mon} do
    check = CheckFn.build("web")
    ManagedMonitor.register(mon, "web", check, 1_000)

    assert :ok = ManagedMonitor.deregister(mon, "web")
    assert {:error, :not_found} = ManagedMonitor.status(mon, "web")
    assert ManagedMonitor.statuses(mon) == %{}
  end

  test "deregistering is idempotent", %{mon: mon} do
    assert :ok = ManagedMonitor.deregister(mon, "nonexistent")
  end

  test "stale check message after deregister has no effect", %{mon: mon} do
    CheckFn.set_result("web", {:error, :boom})
    check = CheckFn.build("web")
    ManagedMonitor.register(mon, "web", check, 1_000)
    ManagedMonitor.deregister(mon, "web")

    send(mon, {:check, "web"})
    _ = ManagedMonitor.statuses(mon)

    assert {:error, :not_found} = ManagedMonitor.status(mon, "web")
    assert Notifications.count_event(:down) == 0
  end

  test "stale maintenance_end after deregister has no effect", %{mon: mon} do
    check = CheckFn.build("web")
    ManagedMonitor.register(mon, "web", check, 1_000)
    ManagedMonitor.maintenance(mon, "web", 5_000)
    ManagedMonitor.deregister(mon, "web")

    send(mon, {:maintenance_end, "web"})
    _ = ManagedMonitor.statuses(mon)

    assert {:error, :not_found} = ManagedMonitor.status(mon, "web")
  end

  test "can re-register a service after deregistering it", %{mon: mon} do
    check = CheckFn.build("web")
    ManagedMonitor.register(mon, "web", check, 1_000)
    ManagedMonitor.deregister(mon, "web")
    assert :ok = ManagedMonitor.register(mon, "web", check, 1_000)

    assert {:ok, %{status: :pending}} = ManagedMonitor.status(mon, "web")
  end

  # -------------------------------------------------------
  # statuses/1 returns all services
  # -------------------------------------------------------

  test "statuses returns a map of all registered services", %{mon: mon} do
    ManagedMonitor.register(mon, "web", CheckFn.build("web"), 1_000)
    ManagedMonitor.register(mon, "db", CheckFn.build("db"), 2_000)
    ManagedMonitor.register(mon, "cache", CheckFn.build("cache"), 500)

    all = ManagedMonitor.statuses(mon)
    assert Map.keys(all) |> Enum.sort() == ["cache", "db", "web"]

    for {_name, info} <- all do
      assert info.status == :pending
    end
  end

  # -------------------------------------------------------
  # Key independence
  # -------------------------------------------------------

  test "failure on one service does not affect another", %{mon: mon} do
    CheckFn.set_result("bad", {:error, :fail})
    CheckFn.set_result("good", :ok)
    ManagedMonitor.register(mon, "bad", CheckFn.build("bad"), 1_000)
    ManagedMonitor.register(mon, "good", CheckFn.build("good"), 1_000)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "bad")
      trigger_check(mon, "good")
    end

    assert {:ok, %{status: :down}} = ManagedMonitor.status(mon, "bad")
    assert {:ok, %{status: :up, consecutive_failures: 0}} = ManagedMonitor.status(mon, "good")
  end

  # -------------------------------------------------------
  # last_check_at tracking
  # -------------------------------------------------------

  test "last_check_at reflects the timestamp of the most recent check", %{mon: mon} do
    CheckFn.set_result("svc", :ok)
    ManagedMonitor.register(mon, "svc", CheckFn.build("svc"), 1_000)

    Clock.advance(1_000)
    trigger_check(mon, "svc")
    assert {:ok, %{last_check_at: 1_000}} = ManagedMonitor.status(mon, "svc")

    Clock.advance(1_000)
    trigger_check(mon, "svc")
    assert {:ok, %{last_check_at: 2_000}} = ManagedMonitor.status(mon, "svc")
  end
end
