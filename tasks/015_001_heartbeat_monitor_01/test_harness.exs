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

  test "notification fires again on a second down after recovery", %{mon: mon} do
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

  # -------------------------------------------------------
  # Real timer-driven scheduling (no injected check messages)
  # -------------------------------------------------------

  # Builds a check function that reports every invocation to the test
  # process, so timer-driven checks can be observed without injecting
  # any messages into the monitor.
  defp reporting_check(service_name, result) do
    parent = self()

    fn ->
      send(parent, {:checked, service_name})
      result
    end
  end

  # Consumes any check reports already sitting in the mailbox.
  defp drain_checks do
    receive do
      {:checked, _name} -> drain_checks()
    after
      0 -> :ok
    end
  end

  test "the monitor itself runs the first check only after interval_ms elapses", %{mon: mon} do
    check = reporting_check("timed", :ok)
    assert :ok = Monitor.register(mon, "timed", check, 300)

    # Registration alone must not run the check; it is scheduled for later.
    refute_receive {:checked, "timed"}, 100

    # Once the interval passes, the monitor's own timer runs the check.
    assert_receive {:checked, "timed"}, 2_000

    assert {:ok, %{status: :up}} = Monitor.status(mon, "timed")
  end

  test "the monitor re-arms its timer so checks repeat every interval", %{mon: mon} do
    check = reporting_check("repeating", :ok)
    assert :ok = Monitor.register(mon, "repeating", check, 20)

    # Each completed check schedules the next one, so reports keep arriving
    # without any help from the test.
    assert_receive {:checked, "repeating"}, 2_000
    assert_receive {:checked, "repeating"}, 2_000
    assert_receive {:checked, "repeating"}, 2_000
  end

  test "deregistering stops timer-driven checks from running", %{mon: mon} do
    check = reporting_check("cancelled", :ok)
    assert :ok = Monitor.register(mon, "cancelled", check, 20)

    assert_receive {:checked, "cancelled"}, 2_000

    assert :ok = Monitor.deregister(mon, "cancelled")
    drain_checks()

    # No pending or future check for a deregistered service may run its
    # check function, even though several intervals go by.
    refute_receive {:checked, "cancelled"}, 300
  end

  test "a manual {:check, name} performs one check and the single chain keeps ticking", %{
    mon: mon
  } do
    check = reporting_check("folded", :ok)
    assert :ok = Monitor.register(mon, "folded", check, 400)

    trigger_check(mon, "folded")
    assert_receive {:checked, "folded"}, 500

    # The manual check folded into the chain (one live timer, cadence reset):
    # the next check arrives timer-driven, with no help from the test.
    assert_receive {:checked, "folded"}, 2_000
  end

  test "manual checks never arm a second chain: no orphan timer resurrects into a re-registration",
       %{mon: mon} do
    check = reporting_check("single_chain", :ok)
    assert :ok = Monitor.register(mon, "single_chain", check, 200)

    # A burst of manual checks. Each must retire the pending chain tick and
    # re-arm — never add an extra chain whose timer ref would be lost.
    for _ <- 1..3, do: trigger_check(mon, "single_chain")

    # Replace the registration with one whose first legitimate tick is far
    # away. Any orphaned 200 ms timer left by the burst would fire into the
    # NEW registration long before that — and must not exist.
    assert :ok = Monitor.deregister(mon, "single_chain")
    drain_checks()

    fresh = reporting_check("single_chain", :ok)
    assert :ok = Monitor.register(mon, "single_chain", fresh, 60_000)

    refute_receive {:checked, "single_chain"}, 600
  end

  # -------------------------------------------------------
  # Sub-threshold failures leave the status untouched
  # -------------------------------------------------------

  test "sub-threshold failures leave a never-checked service exactly :pending", %{mon: mon} do
    CheckFn.set_result("quiet", {:error, :nope})
    Monitor.register(mon, "quiet", CheckFn.build("quiet"), 5_000, 3)

    # First failure: the counter moves, the status must not — a service that
    # has never had a successful check is still :pending.
    Clock.advance(5_000)
    trigger_check(mon, "quiet")

    assert {:ok, %{status: :pending, consecutive_failures: 1, last_check_at: 5_000}} =
             Monitor.status(mon, "quiet")

    # Second failure, still below max_failures: unchanged again.
    Clock.advance(5_000)
    trigger_check(mon, "quiet")

    assert {:ok, %{status: :pending, consecutive_failures: 2}} =
             Monitor.status(mon, "quiet")

    # Only reaching the threshold changes the status.
    Clock.advance(5_000)
    trigger_check(mon, "quiet")

    assert {:ok, %{status: :down, consecutive_failures: 3}} =
             Monitor.status(mon, "quiet")
  end

  test "sub-threshold failures leave an already :up service exactly :up", %{mon: mon} do
    CheckFn.set_result("healthy", :ok)
    Monitor.register(mon, "healthy", CheckFn.build("healthy"), 5_000, 3)

    Clock.advance(5_000)
    trigger_check(mon, "healthy")
    assert {:ok, %{status: :up}} = Monitor.status(mon, "healthy")

    CheckFn.set_result("healthy", {:error, :blip})

    Clock.advance(5_000)
    trigger_check(mon, "healthy")

    assert {:ok, %{status: :up, consecutive_failures: 1}} =
             Monitor.status(mon, "healthy")

    Clock.advance(5_000)
    trigger_check(mon, "healthy")

    assert {:ok, %{status: :up, consecutive_failures: 2}} =
             Monitor.status(mon, "healthy")
  end

  # -------------------------------------------------------
  # :notify defaults to no notification
  # -------------------------------------------------------

  test "a monitor started without :notify survives a down-transition", %{mon: _mon} do
    {:ok, silent} = Monitor.start_link(clock: &Clock.now/0)

    CheckFn.set_result("silent", {:error, :unreachable})
    assert :ok = Monitor.register(silent, "silent", CheckFn.build("silent"), 5_000)

    # Crossing the threshold with no :notify configured must simply skip the
    # notification instead of crashing the server.
    for _ <- 1..3 do
      Clock.advance(5_000)
      trigger_check(silent, "silent")
    end

    assert {:ok, %{status: :down, consecutive_failures: 3}} =
             Monitor.status(silent, "silent")

    assert Notifications.count() == 0

    # The server is still alive and serving calls after the transition, and
    # keeps counting further failures without notifying.
    Clock.advance(5_000)
    trigger_check(silent, "silent")

    assert {:ok, %{status: :down, consecutive_failures: 4}} =
             Monitor.status(silent, "silent")

    assert Notifications.count() == 0
  end

  test "two back-to-back manual checks both run (the drain never eats a user send)", %{mon: mon} do
    test_pid = self()

    Monitor.register(
      mon,
      "svc",
      fn ->
        send(test_pid, :checked)
        :ok
      end,
      60_000
    )

    send(mon, {:check, "svc"})
    send(mon, {:check, "svc"})

    assert_receive :checked, 500
    assert_receive :checked, 500
  end
end
