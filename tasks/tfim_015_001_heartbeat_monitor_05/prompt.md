# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Monitor do
  @moduledoc """
  A GenServer that monitors registered services via periodic heartbeat checks.

  Each service is checked on its own `interval_ms` schedule using
  `Process.send_after/3`. Consecutive failures are counted and, once
  `max_failures` is reached, the service transitions to `:down` and the
  optional `:notify` callback is invoked exactly once per down-transition.
  Recovery resets the counter and re-arms the notification for any future
  down-transition.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type service_name :: term()
  @type status :: :pending | :up | :down
  @type status_info :: %{
          status: status(),
          last_check_at: integer() | nil,
          consecutive_failures: non_neg_integer()
        }

  # Internal service record stored in state.
  #
  # Fields:
  #   * `:check_func`           – zero-arity fn returning `:ok | {:error, reason}`
  #   * `:interval_ms`          – milliseconds between checks
  #   * `:max_failures`         – consecutive-failure threshold before `:down`
  #   * `:status`               – current status atom
  #   * `:last_check_at`        – clock value at the last completed check (nil until first)
  #   * `:consecutive_failures` – running count of uninterrupted failures
  #   * `:notified_down`        – true once we have fired the notify callback for the
  #                               current down-run; prevents duplicate notifications;
  #                               reset to false on recovery so the next down-run
  #                               triggers a fresh notification
  @typep service :: %{
           check_func: (-> :ok | {:error, term()}),
           interval_ms: pos_integer(),
           max_failures: pos_integer(),
           status: status(),
           last_check_at: integer() | nil,
           consecutive_failures: non_neg_integer(),
           notified_down: boolean(),
           timer: reference()
         }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the Monitor GenServer.

  ## Options

    * `:clock`  – zero-arity function returning current time in milliseconds.
                  Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:name`   – passed directly to `GenServer.start_link/3` for registration.
    * `:notify` – `fn service_name, reason -> any()` called once whenever a
                  service transitions to `:down`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name_opt, gen_opts} =
      case Keyword.fetch(opts, :name) do
        {:ok, name} -> {[name: name], []}
        :error -> {[], []}
      end

    GenServer.start_link(__MODULE__, opts, gen_opts ++ name_opt)
  end

  @doc """
  Registers a service for monitoring.

  Returns `:ok` on success, or `{:error, :already_registered}` if a service
  with `service_name` is already registered.
  """
  @spec register(
          GenServer.server(),
          service_name(),
          (-> :ok | {:error, term()}),
          pos_integer(),
          pos_integer()
        ) :: :ok | {:error, :already_registered}
  def register(server, service_name, check_func, interval_ms, max_failures \\ 3) do
    GenServer.call(server, {:register, service_name, check_func, interval_ms, max_failures})
  end

  @doc """
  Returns the current status information for a single service.

  Returns `{:ok, status_info}` or `{:error, :not_found}`.
  """
  @spec status(GenServer.server(), service_name()) ::
          {:ok, status_info()} | {:error, :not_found}
  def status(server, service_name) do
    GenServer.call(server, {:status, service_name})
  end

  @doc """
  Returns a map of every registered service name to its `status_info` map.
  """
  @spec statuses(GenServer.server()) :: %{service_name() => status_info()}
  def statuses(server) do
    GenServer.call(server, :statuses)
  end

  @doc """
  Deregisters a service and cancels any pending check for it.

  Always returns `:ok`, even if the service was not registered.
  """
  @spec deregister(GenServer.server(), service_name()) :: :ok
  def deregister(server, service_name) do
    GenServer.call(server, {:deregister, service_name})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    notify = Keyword.get(opts, :notify, nil)

    {:ok, %{services: %{}, clock: clock, notify: notify}}
  end

  @impl GenServer
  def handle_call({:register, name, check_func, interval_ms, max_failures}, _from, state) do
    if Map.has_key?(state.services, name) do
      {:reply, {:error, :already_registered}, state}
    else
      service = %{
        check_func: check_func,
        interval_ms: interval_ms,
        max_failures: max_failures,
        status: :pending,
        last_check_at: nil,
        consecutive_failures: 0,
        notified_down: false,
        # The live timer of this registration's check chain. Tracking it is
        # what lets deregister/2 really cancel the chain — without it, a
        # deregister followed by a re-registration under the same name would
        # let the OLD chain's next {:check, name} drive the NEW registration
        # (early checks, doubled cadence, doubled failure counting).
        timer: schedule_check(name, interval_ms)
      }

      {:reply, :ok, put_in(state.services[name], service)}
    end
  end

  def handle_call({:status, name}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, service} -> {:reply, {:ok, to_status_info(service)}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:statuses, _from, state) do
    result = Map.new(state.services, fn {name, svc} -> {name, to_status_info(svc)} end)
    {:reply, result, state}
  end

  def handle_call({:deregister, name}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, service} ->
        # Cancel the chain's live timer. If it fired before the cancel, its
        # {:check, name} message is already queued BEHIND this call — drain
        # it, or a later re-registration under the same name would resurrect
        # the old chain (`after 0` cannot block: the message is either queued
        # by now or was never sent).
        Process.cancel_timer(service.timer)

        receive do
          {:check, ^name} -> :ok
        after
          0 -> :ok
        end

        {:reply, :ok, %{state | services: Map.delete(state.services, name)}}

      :error ->
        {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_info({:check, name}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        # Service was deregistered after this message was sent; discard it.
        {:noreply, state}

      {:ok, service} ->
        now = state.clock.()
        result = service.check_func.()

        {new_service, notify?} = apply_check_result(service, result, now)

        # AT MOST ONE live timer per service, unconditionally: cancel the
        # pending timer before re-arming. For a chain tick this is a no-op
        # (its own timer already fired); for a MANUAL `{:check, name}` it
        # retires the pending chain tick so the manual check resets the
        # cadence instead of arming a second chain whose ref would be lost —
        # an orphan that leaks, double-drives the cadence, and can even
        # resurrect into a later re-registration (F23).
        _ = Process.cancel_timer(service.timer)

        receive do
          {:check, ^name} -> :ok
        after
          0 -> :ok
        end

        timer = schedule_check(name, service.interval_ms)
        new_state = put_in(state.services[name], %{new_service | timer: timer})

        if notify? do
          # Extract the reason from the result we already have.
          {:error, reason} = result
          fire_notify(state.notify, name, reason)
        end

        {:noreply, new_state}
    end
  end

  # Catch-all — ignore unexpected messages.
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Returns `{updated_service, notify?}` where `notify?` is true exactly when
  # we should fire the down-transition callback.
  @spec apply_check_result(service(), :ok | {:error, term()}, integer()) ::
          {service(), boolean()}
  defp apply_check_result(service, :ok, now) do
    new_service = %{
      service
      | status: :up,
        last_check_at: now,
        consecutive_failures: 0,
        # Reset so the *next* down-run triggers a fresh notification.
        notified_down: false
    }

    {new_service, false}
  end

  defp apply_check_result(service, {:error, _reason}, now) do
    new_failures = service.consecutive_failures + 1
    threshold_reached = new_failures >= service.max_failures

    # Notify only on the exact transition into :down (not on every failure
    # once already down, and not while still below the threshold).
    notify? = threshold_reached && !service.notified_down

    new_status =
      if threshold_reached do
        :down
      else
        # Stay in whatever status we were in (:pending or a previous state);
        # the service is failing but hasn't crossed the threshold yet.
        service.status
      end

    new_service = %{
      service
      | status: new_status,
        last_check_at: now,
        consecutive_failures: new_failures,
        notified_down: service.notified_down || notify?
    }

    {new_service, notify?}
  end

  @spec schedule_check(service_name(), pos_integer()) :: reference()
  defp schedule_check(name, interval_ms) do
    Process.send_after(self(), {:check, name}, interval_ms)
  end

  @spec to_status_info(service()) :: status_info()
  defp to_status_info(service) do
    %{
      status: service.status,
      last_check_at: service.last_check_at,
      consecutive_failures: service.consecutive_failures
    }
  end

  @spec fire_notify((service_name(), term() -> any()) | nil, service_name(), term()) :: any()
  defp fire_notify(nil, _name, _reason), do: :ok
  defp fire_notify(notify_fn, name, reason), do: notify_fn.(name, reason)
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
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
end
```
