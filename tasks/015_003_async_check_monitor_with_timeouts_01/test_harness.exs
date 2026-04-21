defmodule AsyncMonitorTest do
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

    def set_result(service, result) do
      Agent.update(__MODULE__, &Map.put(&1, service, result))
    end

    def build(service) do
      fn -> Agent.get(__MODULE__, &Map.get(&1, service, :ok)) end
    end

    @doc "Build a check function that blocks forever (for timeout tests)."
    def build_blocking do
      fn -> Process.sleep(:infinity) end
    end
  end

  setup do
    start_supervised!({Clock, 0})
    start_supervised!(Notifications)
    start_supervised!(CheckFn)

    {:ok, pid} =
      AsyncMonitor.start_link(
        clock: &Clock.now/0,
        notify: &Notifications.record/2
      )

    %{mon: pid}
  end

  # Helper: trigger the async check cycle and wait for the result to be
  # processed. We send :schedule_check, then do a synchronous call to
  # ensure both the spawn and the result message have been processed.
  defp trigger_check(mon, service_name) do
    send(mon, {:schedule_check, service_name})
    # First sync: ensures the task is spawned.
    _ = AsyncMonitor.status(mon, service_name)
    # Small sleep to let the Task execute and send its result back.
    Process.sleep(10)
    # Second sync: ensures the result message is processed.
    _ = AsyncMonitor.status(mon, service_name)
  end

  # Helper: trigger a check and then fire the timeout (for timeout tests).
  defp trigger_check_with_timeout(mon, service_name) do
    send(mon, {:schedule_check, service_name})
    # Sync to ensure task is spawned.
    {:ok, _info} = AsyncMonitor.status(mon, service_name)

    # Now manually send the timeout message (the real timer would fire later).
    # We need to get the task_ref, but it's internal. Instead, we send the
    # timeout as if the timer fired — the GenServer will match on the ref.
    # Since we can't easily access the ref, we trigger it by sending the
    # :check_timeout with the current ref by asking the GenServer to process it.
    # In practice, we simulate by waiting briefly then checking status.

    # For testing, we use a very short timeout_ms so the real timer fires.
    Process.sleep(20)
    _ = AsyncMonitor.status(mon, service_name)
  end

  # -------------------------------------------------------
  # Registration
  # -------------------------------------------------------

  test "newly registered service starts in :pending status", %{mon: mon} do
    check = CheckFn.build("web")
    assert :ok = AsyncMonitor.register(mon, "web", check, 5_000)

    assert {:ok, info} = AsyncMonitor.status(mon, "web")
    assert info.status == :pending
    assert info.consecutive_failures == 0
    assert info.last_check_at == nil
    assert info.check_in_flight == false
  end

  test "cannot register the same service name twice", %{mon: mon} do
    check = CheckFn.build("web")
    assert :ok = AsyncMonitor.register(mon, "web", check, 5_000)
    assert {:error, :already_registered} = AsyncMonitor.register(mon, "web", check, 5_000)
  end

  test "status returns :not_found for unregistered service", %{mon: mon} do
    assert {:error, :not_found} = AsyncMonitor.status(mon, "ghost")
  end

  # -------------------------------------------------------
  # Successful checks → :up
  # -------------------------------------------------------

  test "service becomes :up after a successful async check", %{mon: mon} do
    CheckFn.set_result("web", :ok)
    check = CheckFn.build("web")
    AsyncMonitor.register(mon, "web", check, 5_000)

    Clock.advance(5_000)
    trigger_check(mon, "web")

    assert {:ok, info} = AsyncMonitor.status(mon, "web")
    assert info.status == :up
    assert info.consecutive_failures == 0
    assert info.last_check_at == 5_000
    assert info.check_in_flight == false
  end

  # -------------------------------------------------------
  # Failures and :down transition
  # -------------------------------------------------------

  test "service goes :down after max_failures consecutive failures (default 3)", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    AsyncMonitor.register(mon, "db", check, 1_000)

    for _i <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    assert {:ok, %{status: :down, consecutive_failures: 3}} =
             AsyncMonitor.status(mon, "db")
  end

  test "notification fires exactly once on transition to :down", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    AsyncMonitor.register(mon, "db", check, 1_000)

    for _ <- 1..3 do
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
    AsyncMonitor.register(mon, "cache", check, 500, max_failures: 5)

    for _ <- 1..4 do
      Clock.advance(500)
      trigger_check(mon, "cache")
    end

    assert {:ok, %{status: status}} = AsyncMonitor.status(mon, "cache")
    refute status == :down, "should not be :down after only 4 failures with max_failures=5"

    Clock.advance(500)
    trigger_check(mon, "cache")

    assert {:ok, %{status: :down, consecutive_failures: 5}} =
             AsyncMonitor.status(mon, "cache")

    assert Notifications.count() == 1
  end

  # -------------------------------------------------------
  # Timeout handling
  # -------------------------------------------------------

  test "a check that exceeds timeout_ms is treated as a failure", %{mon: mon} do
    blocking = CheckFn.build_blocking()
    # Use very short timeout for testing.
    AsyncMonitor.register(mon, "slow", blocking, 1_000, timeout_ms: 15, max_failures: 1)

    Clock.advance(1_000)
    trigger_check_with_timeout(mon, "slow")

    assert {:ok, %{status: :down, consecutive_failures: c}} = AsyncMonitor.status(mon, "slow")
    assert c >= 1

    # Notification should have fired with reason :timeout.
    assert Notifications.count() >= 1
    [{_name, reason}] = Notifications.all() |> Enum.take(1)
    assert reason == :timeout
  end

  # -------------------------------------------------------
  # Recovery from :down → :up
  # -------------------------------------------------------

  test "a :down service recovers to :up when check succeeds", %{mon: mon} do
    CheckFn.set_result("api", {:error, :crash})
    check = CheckFn.build("api")
    AsyncMonitor.register(mon, "api", check, 1_000)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert {:ok, %{status: :down}} = AsyncMonitor.status(mon, "api")

    CheckFn.set_result("api", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "api")

    assert {:ok, %{status: :up, consecutive_failures: 0}} =
             AsyncMonitor.status(mon, "api")
  end

  test "notification fires again if service goes down a second time after recovery", %{mon: mon} do
    CheckFn.set_result("api", {:error, :crash})
    check = CheckFn.build("api")
    AsyncMonitor.register(mon, "api", check, 1_000)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert Notifications.count() == 1

    CheckFn.set_result("api", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "api")

    CheckFn.set_result("api", {:error, :oom})

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert Notifications.count() == 2
    assert Notifications.all() == [{"api", :crash}, {"api", :oom}]
  end

  # -------------------------------------------------------
  # Success resets failure counter
  # -------------------------------------------------------

  test "a success in between failures resets the counter", %{mon: mon} do
    CheckFn.set_result("svc", {:error, :flaky})
    check = CheckFn.build("svc")
    AsyncMonitor.register(mon, "svc", check, 1_000)

    for _ <- 1..2 do
      Clock.advance(1_000)
      trigger_check(mon, "svc")
    end

    assert {:ok, %{consecutive_failures: 2}} = AsyncMonitor.status(mon, "svc")

    CheckFn.set_result("svc", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "svc")

    assert {:ok, %{consecutive_failures: 0, status: :up}} =
             AsyncMonitor.status(mon, "svc")

    CheckFn.set_result("svc", {:error, :flaky})

    for _ <- 1..2 do
      Clock.advance(1_000)
      trigger_check(mon, "svc")
    end

    assert {:ok, %{status: status}} = AsyncMonitor.status(mon, "svc")
    refute status == :down
  end

  # -------------------------------------------------------
  # Deregistration
  # -------------------------------------------------------

  test "deregistering a service removes it from statuses", %{mon: mon} do
    check = CheckFn.build("web")
    AsyncMonitor.register(mon, "web", check, 1_000)

    assert :ok = AsyncMonitor.deregister(mon, "web")
    assert {:error, :not_found} = AsyncMonitor.status(mon, "web")
    assert AsyncMonitor.statuses(mon) == %{}
  end

  test "deregistering is idempotent", %{mon: mon} do
    assert :ok = AsyncMonitor.deregister(mon, "nonexistent")
  end

  test "stale schedule message after deregister has no effect", %{mon: mon} do
    CheckFn.set_result("web", {:error, :boom})
    check = CheckFn.build("web")
    AsyncMonitor.register(mon, "web", check, 1_000)
    AsyncMonitor.deregister(mon, "web")

    send(mon, {:schedule_check, "web"})
    _ = AsyncMonitor.statuses(mon)
    Process.sleep(10)
    _ = AsyncMonitor.statuses(mon)

    assert {:error, :not_found} = AsyncMonitor.status(mon, "web")
    assert Notifications.count() == 0
  end

  test "can re-register a service after deregistering it", %{mon: mon} do
    check = CheckFn.build("web")
    AsyncMonitor.register(mon, "web", check, 1_000)
    AsyncMonitor.deregister(mon, "web")
    assert :ok = AsyncMonitor.register(mon, "web", check, 1_000)

    assert {:ok, %{status: :pending}} = AsyncMonitor.status(mon, "web")
  end

  # -------------------------------------------------------
  # statuses/1 returns all services
  # -------------------------------------------------------

  test "statuses returns a map of all registered services", %{mon: mon} do
    AsyncMonitor.register(mon, "web", CheckFn.build("web"), 1_000)
    AsyncMonitor.register(mon, "db", CheckFn.build("db"), 2_000)
    AsyncMonitor.register(mon, "cache", CheckFn.build("cache"), 500)

    all = AsyncMonitor.statuses(mon)
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
    AsyncMonitor.register(mon, "bad", CheckFn.build("bad"), 1_000)
    AsyncMonitor.register(mon, "good", CheckFn.build("good"), 1_000)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "bad")
      trigger_check(mon, "good")
    end

    assert {:ok, %{status: :down}} = AsyncMonitor.status(mon, "bad")
    assert {:ok, %{status: :up, consecutive_failures: 0}} = AsyncMonitor.status(mon, "good")
  end

  # -------------------------------------------------------
  # last_check_at tracking
  # -------------------------------------------------------

  test "last_check_at reflects the timestamp of the most recent check", %{mon: mon} do
    CheckFn.set_result("svc", :ok)
    AsyncMonitor.register(mon, "svc", CheckFn.build("svc"), 1_000)

    Clock.advance(1_000)
    trigger_check(mon, "svc")
    assert {:ok, %{last_check_at: 1_000}} = AsyncMonitor.status(mon, "svc")

    Clock.advance(1_000)
    trigger_check(mon, "svc")
    assert {:ok, %{last_check_at: 2_000}} = AsyncMonitor.status(mon, "svc")
  end

  # -------------------------------------------------------
  # Notification reason accuracy
  # -------------------------------------------------------

  test "notification carries the reason from the final failing check", %{mon: mon} do
    check = CheckFn.build("svc")
    AsyncMonitor.register(mon, "svc", check, 1_000)

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
