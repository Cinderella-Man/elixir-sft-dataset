defmodule RateMonitorTest do
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

    def record(service, failure_rate) do
      Agent.update(__MODULE__, &[{service, failure_rate} | &1])
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
      RateMonitor.start_link(
        clock: &Clock.now/0,
        notify: &Notifications.record/2
      )

    %{mon: pid}
  end

  defp trigger_check(mon, service_name) do
    send(mon, {:check, service_name})
    _ = RateMonitor.status(mon, service_name)
  end

  # -------------------------------------------------------
  # Registration
  # -------------------------------------------------------

  test "newly registered service starts in :pending status", %{mon: mon} do
    check = CheckFn.build("web")
    assert :ok = RateMonitor.register(mon, "web", check, 5_000)

    assert {:ok, info} = RateMonitor.status(mon, "web")
    assert info.status == :pending
    assert info.failure_rate == 0.0
    assert info.checks_in_window == 0
    assert info.last_check_at == nil
  end

  test "cannot register the same service name twice", %{mon: mon} do
    check = CheckFn.build("web")
    assert :ok = RateMonitor.register(mon, "web", check, 5_000)
    assert {:error, :already_registered} = RateMonitor.register(mon, "web", check, 5_000)
  end

  test "status returns :not_found for unregistered service", %{mon: mon} do
    assert {:error, :not_found} = RateMonitor.status(mon, "ghost")
  end

  # -------------------------------------------------------
  # Successful checks → :up
  # -------------------------------------------------------

  test "service becomes :up after a successful check", %{mon: mon} do
    CheckFn.set_result("web", :ok)
    check = CheckFn.build("web")
    RateMonitor.register(mon, "web", check, 5_000)

    Clock.advance(5_000)
    trigger_check(mon, "web")

    assert {:ok, info} = RateMonitor.status(mon, "web")
    assert info.status == :up
    assert info.failure_rate == 0.0
    assert info.last_check_at == 5_000
  end

  # -------------------------------------------------------
  # Failure rate and :down transition
  # -------------------------------------------------------

  test "service does NOT go :down before window is full", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    # window_size=5, threshold=0.6
    RateMonitor.register(mon, "db", check, 1_000, window_size: 5, threshold: 0.6)

    # 4 failures — window not full yet (need 5 checks)
    for _i <- 1..4 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    assert {:ok, info} = RateMonitor.status(mon, "db")
    refute info.status == :down, "should not be :down before window is full"
    assert info.checks_in_window == 4
  end

  test "service goes :down when failure rate >= threshold with full window", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    RateMonitor.register(mon, "db", check, 1_000, window_size: 5, threshold: 0.6)

    # 5 failures → rate = 1.0 >= 0.6
    for _ <- 1..5 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    assert {:ok, %{status: :down, failure_rate: rate}} = RateMonitor.status(mon, "db")
    assert rate == 1.0
  end

  test "notification fires exactly once on transition to :down", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    RateMonitor.register(mon, "db", check, 1_000, window_size: 3, threshold: 0.6)

    # 3 failures → rate = 1.0 >= 0.6 → :down
    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    assert Notifications.count() == 1

    # A 4th failure should NOT trigger another notification
    Clock.advance(1_000)
    trigger_check(mon, "db")

    assert Notifications.count() == 1
  end

  test "notification includes the failure rate", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    RateMonitor.register(mon, "db", check, 1_000, window_size: 3, threshold: 0.6)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    [{name, rate}] = Notifications.all()
    assert name == "db"
    assert rate == 1.0
  end

  # -------------------------------------------------------
  # Mixed results — rate-based detection
  # -------------------------------------------------------

  test "intermittent failures below threshold keep service :up", %{mon: mon} do
    check = CheckFn.build("flaky")
    RateMonitor.register(mon, "flaky", check, 1_000, window_size: 5, threshold: 0.6)

    # Pattern: ok, error, ok, ok, error → 2/5 = 0.4 < 0.6
    results = [:ok, {:error, :flaky}, :ok, :ok, {:error, :flaky}]

    for result <- results do
      CheckFn.set_result("flaky", result)
      Clock.advance(1_000)
      trigger_check(mon, "flaky")
    end

    assert {:ok, %{status: :up, failure_rate: rate}} = RateMonitor.status(mon, "flaky")
    assert_in_delta rate, 0.4, 0.01
    assert Notifications.count() == 0
  end

  test "failure rate at exactly threshold triggers :down", %{mon: mon} do
    check = CheckFn.build("svc")
    # window_size=5, threshold=0.6 → need 3/5 errors = 0.6
    RateMonitor.register(mon, "svc", check, 1_000, window_size: 5, threshold: 0.6)

    # 2 ok then 3 errors → 3/5 = 0.6
    results = [:ok, :ok, {:error, :a}, {:error, :b}, {:error, :c}]

    for result <- results do
      CheckFn.set_result("svc", result)
      Clock.advance(1_000)
      trigger_check(mon, "svc")
    end

    assert {:ok, %{status: :down, failure_rate: rate}} = RateMonitor.status(mon, "svc")
    assert_in_delta rate, 0.6, 0.01
    assert Notifications.count() == 1
  end

  # -------------------------------------------------------
  # Recovery from :down → :up
  # -------------------------------------------------------

  test "a :down service recovers when failure rate drops below threshold", %{mon: mon} do
    check = CheckFn.build("api")
    RateMonitor.register(mon, "api", check, 1_000, window_size: 5, threshold: 0.6)

    # Fill window with all errors → :down
    CheckFn.set_result("api", {:error, :crash})

    for _ <- 1..5 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert {:ok, %{status: :down}} = RateMonitor.status(mon, "api")

    # Now successes push errors out of the window
    # After 1 ok: [err, err, err, err, ok] → 4/5 = 0.8 ≥ 0.6 → still :down
    CheckFn.set_result("api", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "api")
    assert {:ok, %{status: :down}} = RateMonitor.status(mon, "api")

    # After 2 ok: [err, err, err, ok, ok] → 3/5 = 0.6 → still :down
    Clock.advance(1_000)
    trigger_check(mon, "api")
    assert {:ok, %{status: :down}} = RateMonitor.status(mon, "api")

    # After 3 ok: [err, err, ok, ok, ok] → 2/5 = 0.4 < 0.6 → :up!
    Clock.advance(1_000)
    trigger_check(mon, "api")
    assert {:ok, %{status: :up, failure_rate: rate}} = RateMonitor.status(mon, "api")
    assert_in_delta rate, 0.4, 0.01
  end

  test "notification fires again if service goes down a second time after recovery", %{mon: mon} do
    check = CheckFn.build("api")
    RateMonitor.register(mon, "api", check, 1_000, window_size: 3, threshold: 0.6)

    # First down: 3 errors
    CheckFn.set_result("api", {:error, :crash})

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert Notifications.count() == 1

    # Recover: 3 successes push all errors out → [ok, ok, ok] → rate = 0.0
    CheckFn.set_result("api", :ok)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert {:ok, %{status: :up}} = RateMonitor.status(mon, "api")

    # Second down: 3 errors again
    CheckFn.set_result("api", {:error, :oom})

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert Notifications.count() == 2
  end

  # -------------------------------------------------------
  # Window sliding behavior
  # -------------------------------------------------------

  test "old results are evicted from the window", %{mon: mon} do
    check = CheckFn.build("svc")
    RateMonitor.register(mon, "svc", check, 1_000, window_size: 3, threshold: 0.6)

    # 3 errors → [err, err, err] → :down
    CheckFn.set_result("svc", {:error, :x})

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "svc")
    end

    assert {:ok, %{status: :down}} = RateMonitor.status(mon, "svc")

    # 3 successes → [ok, ok, ok] — old errors are fully evicted
    CheckFn.set_result("svc", :ok)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "svc")
    end

    assert {:ok, %{status: :up, failure_rate: +0.0, checks_in_window: 3}} =
             RateMonitor.status(mon, "svc")
  end

  test "checks_in_window never exceeds window_size", %{mon: mon} do
    check = CheckFn.build("svc")
    RateMonitor.register(mon, "svc", check, 1_000, window_size: 3)

    CheckFn.set_result("svc", :ok)

    for _ <- 1..10 do
      Clock.advance(1_000)
      trigger_check(mon, "svc")
    end

    assert {:ok, %{checks_in_window: 3}} = RateMonitor.status(mon, "svc")
  end

  # -------------------------------------------------------
  # Custom window_size and threshold
  # -------------------------------------------------------

  test "custom window_size and threshold are respected", %{mon: mon} do
    check = CheckFn.build("cache")
    # window_size=4, threshold=0.75 → need 3/4 errors
    RateMonitor.register(mon, "cache", check, 500, window_size: 4, threshold: 0.75)

    # 2 errors, 2 ok → rate = 0.5 < 0.75
    CheckFn.set_result("cache", {:error, :conn_refused})
    Clock.advance(500)
    trigger_check(mon, "cache")
    Clock.advance(500)
    trigger_check(mon, "cache")

    CheckFn.set_result("cache", :ok)
    Clock.advance(500)
    trigger_check(mon, "cache")
    Clock.advance(500)
    trigger_check(mon, "cache")

    assert {:ok, %{status: :up}} = RateMonitor.status(mon, "cache")
    assert Notifications.count() == 0
  end

  # -------------------------------------------------------
  # Deregistration
  # -------------------------------------------------------

  test "deregistering a service removes it from statuses", %{mon: mon} do
    check = CheckFn.build("web")
    RateMonitor.register(mon, "web", check, 1_000)

    assert :ok = RateMonitor.deregister(mon, "web")
    assert {:error, :not_found} = RateMonitor.status(mon, "web")
    assert RateMonitor.statuses(mon) == %{}
  end

  test "deregistering is idempotent", %{mon: mon} do
    assert :ok = RateMonitor.deregister(mon, "nonexistent")
  end

  test "stale check message after deregister has no effect", %{mon: mon} do
    CheckFn.set_result("web", {:error, :boom})
    check = CheckFn.build("web")
    RateMonitor.register(mon, "web", check, 1_000)
    RateMonitor.deregister(mon, "web")

    send(mon, {:check, "web"})
    _ = RateMonitor.statuses(mon)

    assert {:error, :not_found} = RateMonitor.status(mon, "web")
    assert Notifications.count() == 0
  end

  test "can re-register a service after deregistering it", %{mon: mon} do
    check = CheckFn.build("web")
    RateMonitor.register(mon, "web", check, 1_000)
    RateMonitor.deregister(mon, "web")
    assert :ok = RateMonitor.register(mon, "web", check, 1_000)

    assert {:ok, %{status: :pending, checks_in_window: 0}} =
             RateMonitor.status(mon, "web")
  end

  # -------------------------------------------------------
  # statuses/1 returns all services
  # -------------------------------------------------------

  test "statuses returns a map of all registered services", %{mon: mon} do
    RateMonitor.register(mon, "web", CheckFn.build("web"), 1_000)
    RateMonitor.register(mon, "db", CheckFn.build("db"), 2_000)
    RateMonitor.register(mon, "cache", CheckFn.build("cache"), 500)

    all = RateMonitor.statuses(mon)
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
    RateMonitor.register(mon, "bad", CheckFn.build("bad"), 1_000, window_size: 3, threshold: 0.6)
    RateMonitor.register(mon, "good", CheckFn.build("good"), 1_000)

    for _ <- 1..5 do
      Clock.advance(1_000)
      trigger_check(mon, "bad")
      trigger_check(mon, "good")
    end

    assert {:ok, %{status: :down}} = RateMonitor.status(mon, "bad")
    assert {:ok, %{status: :up, failure_rate: +0.0}} = RateMonitor.status(mon, "good")
  end

  # -------------------------------------------------------
  # last_check_at tracking
  # -------------------------------------------------------

  test "last_check_at reflects the timestamp of the most recent check", %{mon: mon} do
    CheckFn.set_result("svc", :ok)
    RateMonitor.register(mon, "svc", CheckFn.build("svc"), 1_000)

    Clock.advance(1_000)
    trigger_check(mon, "svc")
    assert {:ok, %{last_check_at: 1_000}} = RateMonitor.status(mon, "svc")

    Clock.advance(1_000)
    trigger_check(mon, "svc")
    assert {:ok, %{last_check_at: 2_000}} = RateMonitor.status(mon, "svc")
  end
end
