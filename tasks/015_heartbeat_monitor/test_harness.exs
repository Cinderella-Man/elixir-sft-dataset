defmodule MonitorTest do
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

    def record(service, reason) do
      Agent.update(__MODULE__, &[{service, reason} | &1])
    end

    def all, do: Agent.get(__MODULE__, &Enum.reverse/1)
    def count, do: Agent.get(__MODULE__, &length/1)
    def clear, do: Agent.update(__MODULE__, fn _ -> [] end)
  end

  # --- Controllable check function ---

  defmodule CheckFn do
    use Agent

    def start_link(_) do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    @doc "Set what a given service's check function will return."
    def set_result(service, result) do
      Agent.update(__MODULE__, &Map.put(&1, service, result))
    end

    @doc "Build a zero-arity check function for the given service key."
    def build(service) do
      fn -> Agent.get(__MODULE__, &Map.get(&1, service, :ok)) end
    end
  end

  setup do
    start_supervised!({Clock, 0})
    start_supervised!(Notifications)
    start_supervised!(CheckFn)

    {:ok, pid} =
      Monitor.start_link(
        clock: &Clock.now/0,
        notify: &Notifications.record/2
      )

    %{mon: pid}
  end

  # Helper: trigger the check message for a service manually and wait
  # for the GenServer to process it.
  defp trigger_check(mon, service_name) do
    send(mon, {:check, service_name})
    # Synchronise by doing a call to ensure the message above was processed
    _ = Monitor.status(mon, service_name)
  end

  # -------------------------------------------------------
  # Registration
  # -------------------------------------------------------

  test "newly registered service starts in :pending status", %{mon: mon} do
    check = CheckFn.build("web")
    assert :ok = Monitor.register(mon, "web", check, 5_000)

    assert {:ok, info} = Monitor.status(mon, "web")
    assert info.status == :pending
    assert info.consecutive_failures == 0
    assert info.last_check_at == nil
  end

  test "cannot register the same service name twice", %{mon: mon} do
    check = CheckFn.build("web")
    assert :ok = Monitor.register(mon, "web", check, 5_000)
    assert {:error, :already_registered} = Monitor.register(mon, "web", check, 5_000)
  end

  test "status returns :not_found for unregistered service", %{mon: mon} do
    assert {:error, :not_found} = Monitor.status(mon, "ghost")
  end

  # -------------------------------------------------------
  # Successful checks → :up
  # -------------------------------------------------------

  test "service becomes :up after a successful check", %{mon: mon} do
    CheckFn.set_result("web", :ok)
    check = CheckFn.build("web")
    Monitor.register(mon, "web", check, 5_000)

    Clock.advance(5_000)
    trigger_check(mon, "web")

    assert {:ok, info} = Monitor.status(mon, "web")
    assert info.status == :up
    assert info.consecutive_failures == 0
    assert info.last_check_at == 5_000
  end

  # -------------------------------------------------------
  # Failures and :down transition
  # -------------------------------------------------------

  test "service goes :down after max_failures consecutive failures (default 3)", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    Monitor.register(mon, "db", check, 1_000)

    # Failure 1
    Clock.advance(1_000)
    trigger_check(mon, "db")
    assert {:ok, %{status: s1, consecutive_failures: 1}} = Monitor.status(mon, "db")
    # Should still be :pending or :up depending on implementation —
    # the key point is it's not :down yet
    assert s1 in [:pending, :up] or s1 != :down

    # Failure 2
    Clock.advance(1_000)
    trigger_check(mon, "db")
    assert {:ok, %{consecutive_failures: 2}} = Monitor.status(mon, "db")

    # Failure 3 → transitions to :down
    Clock.advance(1_000)
    trigger_check(mon, "db")

    assert {:ok, %{status: :down, consecutive_failures: 3}} =
             Monitor.status(mon, "db")
  end

  test "notification fires exactly once on transition to :down", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    Monitor.register(mon, "db", check, 1_000)

    # Drive through 3 failures
    for _i <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    assert Notifications.all() == [{"db", :timeout}]

    # A 4th failure should NOT trigger another notification
    Clock.advance(1_000)
    trigger_check(mon, "db")

    assert Notifications.count() == 1
  end

  test "custom max_failures is respected", %{mon: mon} do
    CheckFn.set_result("cache", {:error, :conn_refused})
    check = CheckFn.build("cache")
    Monitor.register(mon, "cache", check, 500, 5)

    for _ <- 1..4 do
      Clock.advance(500)
      trigger_check(mon, "cache")
    end

    assert {:ok, %{status: status}} = Monitor.status(mon, "cache")
    refute status == :down, "should not be :down after only 4 failures with max_failures=5"

    Clock.advance(500)
    trigger_check(mon, "cache")

    assert {:ok, %{status: :down, consecutive_failures: 5}} =
             Monitor.status(mon, "cache")

    assert Notifications.count() == 1
  end

  # -------------------------------------------------------
  # Recovery from :down → :up
  # -------------------------------------------------------

  test "a :down service recovers to :up when check succeeds", %{mon: mon} do
    CheckFn.set_result("api", {:error, :crash})
    check = CheckFn.build("api")
    Monitor.register(mon, "api", check, 1_000)

    # Drive to :down
    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert {:ok, %{status: :down}} = Monitor.status(mon, "api")

    # Service recovers
    CheckFn.set_result("api", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "api")

    assert {:ok, %{status: :up, consecutive_failures: 0}} =
             Monitor.status(mon, "api")
  end

  test "notification fires again if service goes down a second time after recovery", %{mon: mon} do
    CheckFn.set_result("api", {:error, :crash})
    check = CheckFn.build("api")
    Monitor.register(mon, "api", check, 1_000)

    # First down
    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert Notifications.count() == 1

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

    assert Notifications.count() == 2
    assert Notifications.all() == [{"api", :crash}, {"api", :oom}]
  end

  # -------------------------------------------------------
  # A successful check resets the failure counter
  # -------------------------------------------------------

  test "a success in between failures resets the counter", %{mon: mon} do
    CheckFn.set_result("svc", {:error, :flaky})
    check = CheckFn.build("svc")
    Monitor.register(mon, "svc", check, 1_000)

    # 2 failures
    for _ <- 1..2 do
      Clock.advance(1_000)
      trigger_check(mon, "svc")
    end

    assert {:ok, %{consecutive_failures: 2}} = Monitor.status(mon, "svc")

    # One success → resets
    CheckFn.set_result("svc", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "svc")

    assert {:ok, %{consecutive_failures: 0, status: :up}} =
             Monitor.status(mon, "svc")

    # 2 more failures → still not :down (counter started over)
    CheckFn.set_result("svc", {:error, :flaky})

    for _ <- 1..2 do
      Clock.advance(1_000)
      trigger_check(mon, "svc")
    end

    assert {:ok, %{status: status}} = Monitor.status(mon, "svc")
    refute status == :down
  end

  # -------------------------------------------------------
  # Deregistration
  # -------------------------------------------------------

  test "deregistering a service removes it from statuses", %{mon: mon} do
    check = CheckFn.build("web")
    Monitor.register(mon, "web", check, 1_000)

    assert :ok = Monitor.deregister(mon, "web")
    assert {:error, :not_found} = Monitor.status(mon, "web")
    assert Monitor.statuses(mon) == %{}
  end

  test "deregistering is idempotent", %{mon: mon} do
    assert :ok = Monitor.deregister(mon, "nonexistent")
  end

  test "stale check message after deregister has no effect", %{mon: mon} do
    CheckFn.set_result("web", {:error, :boom})
    check = CheckFn.build("web")
    Monitor.register(mon, "web", check, 1_000)
    Monitor.deregister(mon, "web")

    # Simulate a stale timer message arriving
    send(mon, {:check, "web"})
    _ = Monitor.statuses(mon)

    assert {:error, :not_found} = Monitor.status(mon, "web")
    assert Notifications.count() == 0
  end

  test "can re-register a service after deregistering it", %{mon: mon} do
    check = CheckFn.build("web")
    Monitor.register(mon, "web", check, 1_000)
    Monitor.deregister(mon, "web")
    assert :ok = Monitor.register(mon, "web", check, 1_000)

    assert {:ok, %{status: :pending}} = Monitor.status(mon, "web")
  end

  # -------------------------------------------------------
  # statuses/1 returns all services
  # -------------------------------------------------------

  test "statuses returns a map of all registered services", %{mon: mon} do
    Monitor.register(mon, "web", CheckFn.build("web"), 1_000)
    Monitor.register(mon, "db", CheckFn.build("db"), 2_000)
    Monitor.register(mon, "cache", CheckFn.build("cache"), 500)

    all = Monitor.statuses(mon)
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
    Monitor.register(mon, "bad", CheckFn.build("bad"), 1_000)
    Monitor.register(mon, "good", CheckFn.build("good"), 1_000)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "bad")
      trigger_check(mon, "good")
    end

    assert {:ok, %{status: :down}} = Monitor.status(mon, "bad")
    assert {:ok, %{status: :up, consecutive_failures: 0}} = Monitor.status(mon, "good")
  end

  # -------------------------------------------------------
  # last_check_at tracking
  # -------------------------------------------------------

  test "last_check_at reflects the timestamp of the most recent check", %{mon: mon} do
    CheckFn.set_result("svc", :ok)
    Monitor.register(mon, "svc", CheckFn.build("svc"), 1_000)

    Clock.advance(1_000)
    trigger_check(mon, "svc")
    assert {:ok, %{last_check_at: 1_000}} = Monitor.status(mon, "svc")

    Clock.advance(1_000)
    trigger_check(mon, "svc")
    assert {:ok, %{last_check_at: 2_000}} = Monitor.status(mon, "svc")
  end

  # -------------------------------------------------------
  # Notification reason accuracy
  # -------------------------------------------------------

  test "notification carries the reason from the final failing check", %{mon: mon} do
    check = CheckFn.build("svc")
    Monitor.register(mon, "svc", check, 1_000)

    CheckFn.set_result("svc", {:error, :first_issue})
    Clock.advance(1_000)
    trigger_check(mon, "svc")

    CheckFn.set_result("svc", {:error, :second_issue})
    Clock.advance(1_000)
    trigger_check(mon, "svc")

    CheckFn.set_result("svc", {:error, :final_issue})
    Clock.advance(1_000)
    trigger_check(mon, "svc")

    assert [{"svc", :final_issue}] = Notifications.all()
  end
end
