# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

```elixir
defmodule ManagedMonitor do
  @moduledoc """
  A GenServer that monitors registered services via periodic heartbeat checks
  with support for maintenance windows and manual pause/resume.

  Services can be paused (checks skipped entirely) or placed in maintenance
  mode (checks run but failures are suppressed). Maintenance windows
  auto-expire after a configured duration.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type service_name :: term()
  @type status :: :pending | :up | :down | :paused | :maintenance
  @type status_info :: %{
          status: status(),
          last_check_at: integer() | nil,
          consecutive_failures: non_neg_integer(),
          maintenance_ends_at: integer() | nil
        }

  @typep mode :: :active | :paused | :maintenance
  @typep health :: :pending | :up | :down

  @typep service :: %{
           check_func: (-> :ok | {:error, term()}),
           interval_ms: pos_integer(),
           max_failures: pos_integer(),
           health: health(),
           mode: mode(),
           last_check_at: integer() | nil,
           consecutive_failures: non_neg_integer(),
           notified_down: boolean(),
           maintenance_ends_at: integer() | nil,
           maintenance_timer: reference() | nil
         }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name_opt, gen_opts} =
      case Keyword.fetch(opts, :name) do
        {:ok, name} -> {[name: name], []}
        :error -> {[], []}
      end

    GenServer.start_link(__MODULE__, opts, gen_opts ++ name_opt)
  end

  @doc "Registers `service_name` with `check_func` every `interval_ms`. Returns `:ok`, or `{:error, :already_registered}` if `service_name` is already registered."
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

  @spec status(GenServer.server(), service_name()) ::
          {:ok, status_info()} | {:error, :not_found}
  def status(server, service_name) do
    GenServer.call(server, {:status, service_name})
  end

  @spec statuses(GenServer.server()) :: %{service_name() => status_info()}
  def statuses(server) do
    GenServer.call(server, :statuses)
  end

  @spec deregister(GenServer.server(), service_name()) :: :ok
  def deregister(server, service_name) do
    GenServer.call(server, {:deregister, service_name})
  end

  @spec pause(GenServer.server(), service_name()) :: :ok | {:error, :not_found}
  def pause(server, service_name) do
    GenServer.call(server, {:pause, service_name})
  end

  @spec resume(GenServer.server(), service_name()) ::
          :ok | {:error, :not_found} | {:error, :not_paused}
  def resume(server, service_name) do
    GenServer.call(server, {:resume, service_name})
  end

  @spec maintenance(GenServer.server(), service_name(), pos_integer()) ::
          :ok | {:error, :not_found}
  def maintenance(server, service_name, duration_ms) do
    GenServer.call(server, {:maintenance, service_name, duration_ms})
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
        health: :pending,
        mode: :active,
        last_check_at: nil,
        consecutive_failures: 0,
        notified_down: false,
        maintenance_ends_at: nil,
        maintenance_timer: nil,
        check_timer: nil
      }

      service = %{service | check_timer: schedule_check(name, interval_ms)}

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
        # Kill the whole check chain: the armed timer AND any {:check, name}
        # already sitting in the mailbox — the prompt's rule is that the old
        # registration's leftover timers must not drive a re-registration.
        if service.check_timer, do: Process.cancel_timer(service.check_timer)

        receive do
          {:check, ^name} -> :ok
        after
          0 -> :ok
        end

        # The maintenance-expiry timer is a leftover timer too: cancelled and
        # drained the same way, or it would end a re-registration's NEW
        # maintenance window at the old registration's deadline.
        _ = cancel_maintenance_timer(service, name)

      :error ->
        :ok
    end

    {:reply, :ok, %{state | services: Map.delete(state.services, name)}}
  end

  def handle_call({:pause, name}, _from, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, service} ->
        new_service = %{service | mode: :paused, maintenance_ends_at: nil}
        {:reply, :ok, put_in(state.services[name], new_service)}
    end
  end

  def handle_call({:resume, name}, _from, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, %{mode: mode} = service} when mode in [:paused, :maintenance] ->
        # A manual resume from maintenance must kill the pending expiry, or a
        # LATER maintenance session would be ended early by this session's
        # leftover timer (same resurrection class as deregister's — see
        # handle_call({:deregister, ...})).
        service = cancel_maintenance_timer(service, name)
        new_service = %{service | mode: :active, maintenance_ends_at: nil}
        {:reply, :ok, put_in(state.services[name], new_service)}

      {:ok, _service} ->
        {:reply, {:error, :not_paused}, state}
    end
  end

  def handle_call({:maintenance, name, duration_ms}, _from, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, service} ->
        now = state.clock.()
        ends_at = now + duration_ms

        # Re-entering maintenance REPLACES the duration: the previous session's
        # expiry must never fire, or extending a window (say 100ms -> 10s)
        # would end at the OLD deadline with a spurious :maintenance_ended
        # (probe-proven 2026-07-15). Cancel the tracked timer AND drain an
        # already-queued expiry before arming the new one.
        service = cancel_maintenance_timer(service, name)
        timer = Process.send_after(self(), {:maintenance_end, name}, duration_ms)

        new_service = %{
          service
          | mode: :maintenance,
            maintenance_ends_at: ends_at,
            maintenance_timer: timer
        }

        new_state = put_in(state.services[name], new_service)

        fire_notify(state.notify, name, :maintenance_started, duration_ms)

        {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_info({:check, name}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:noreply, state}

      {:ok, %{mode: :paused} = service} ->
        # Paused: skip the check but keep scheduling (one chain, fresh ref).
        service = rearm(service, name)
        {:noreply, put_in(state.services[name], service)}

      {:ok, %{mode: :maintenance} = service} ->
        now = state.clock.()
        result = service.check_func.()

        new_service = rearm(apply_maintenance_check(service, result, now), name)

        {:noreply, put_in(state.services[name], new_service)}

      {:ok, service} ->
        now = state.clock.()
        result = service.check_func.()

        {new_service, events} = apply_active_check(service, result, now)
        new_service = rearm(new_service, name)

        new_state = put_in(state.services[name], new_service)

        for {event, detail} <- events do
          fire_notify(state.notify, name, event, detail)
        end

        {:noreply, new_state}
    end
  end

  def handle_info({:maintenance_end, name}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        # Service was deregistered; discard.
        {:noreply, state}

      {:ok, %{mode: :maintenance} = service} ->
        new_service = %{service | mode: :active, maintenance_ends_at: nil, maintenance_timer: nil}

        fire_notify(state.notify, name, :maintenance_ended, nil)

        {:noreply, put_in(state.services[name], new_service)}

      {:ok, _service} ->
        # Service is no longer in maintenance (e.g., was resumed manually).
        # Stale timer — discard.
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Active mode check: normal failure counting and status transitions.
  @spec apply_active_check(service(), :ok | {:error, term()}, integer()) ::
          {service(), list({atom(), term()})}
  defp apply_active_check(service, :ok, now) do
    was_down = service.health == :down

    new_service = %{
      service
      | health: :up,
        last_check_at: now,
        consecutive_failures: 0,
        notified_down: false
    }

    events = if was_down, do: [{:recovered, nil}], else: []

    {new_service, events}
  end

  defp apply_active_check(service, {:error, reason}, now) do
    new_failures = service.consecutive_failures + 1
    threshold_reached = new_failures >= service.max_failures

    notify? = threshold_reached && !service.notified_down

    new_health = if threshold_reached, do: :down, else: service.health

    new_service = %{
      service
      | health: new_health,
        last_check_at: now,
        consecutive_failures: new_failures,
        notified_down: service.notified_down || notify?
    }

    events = if notify?, do: [{:down, reason}], else: []

    {new_service, events}
  end

  # Maintenance mode check: successes update health, failures are suppressed.
  @spec apply_maintenance_check(service(), :ok | {:error, term()}, integer()) :: service()
  defp apply_maintenance_check(service, :ok, now) do
    %{
      service
      | health: :up,
        last_check_at: now,
        consecutive_failures: 0,
        notified_down: false
    }
  end

  defp apply_maintenance_check(service, {:error, _reason}, now) do
    # Failures during maintenance are observed (last_check_at updates) but
    # do NOT increment the failure counter or trigger :down.
    %{service | last_check_at: now}
  end

  @spec schedule_check(service_name(), pos_integer()) :: reference()
  # Cancel a service's pending maintenance-expiry timer AND drain an
  # already-queued {:maintenance_end, name} for it. Cancelling alone is not
  # enough: a timer that fired before the cancel has its message queued BEHIND
  # the current call, and it would end the wrong (newer) maintenance session
  # (`after 0` cannot block: the message is either queued by now or was never
  # sent — the same argument as deregister's drain).
  @spec cancel_maintenance_timer(service(), service_name()) :: service()
  defp cancel_maintenance_timer(%{maintenance_timer: nil} = service, _name), do: service

  defp cancel_maintenance_timer(%{maintenance_timer: timer} = service, name) do
    Process.cancel_timer(timer)

    receive do
      {:maintenance_end, ^name} -> :ok
    after
      0 -> :ok
    end

    %{service | maintenance_timer: nil}
  end

  defp schedule_check(name, interval_ms) do
    Process.send_after(self(), {:check, name}, interval_ms)
  end

  # One chain per service, always: cancel whatever is armed before arming the
  # next timer, so neither a manual {:check, name} trigger nor a stale chain
  # can multiply the check rate.
  defp rearm(service, name) do
    if service.check_timer, do: Process.cancel_timer(service.check_timer)
    %{service | check_timer: schedule_check(name, service.interval_ms)}
  end

  # Compute the reported status from the internal health + mode.
  @spec reported_status(service()) :: status()
  defp reported_status(%{mode: :paused}), do: :paused
  defp reported_status(%{mode: :maintenance}), do: :maintenance
  defp reported_status(%{health: health}), do: health

  @spec to_status_info(service()) :: status_info()
  defp to_status_info(service) do
    %{
      status: reported_status(service),
      last_check_at: service.last_check_at,
      consecutive_failures: service.consecutive_failures,
      maintenance_ends_at: service.maintenance_ends_at
    }
  end

  @spec fire_notify(
          (service_name(), atom(), term() -> any()) | nil,
          service_name(),
          atom(),
          term()
        ) :: any()
  defp fire_notify(nil, _name, _event, _detail), do: :ok
  defp fire_notify(notify_fn, name, event, detail), do: notify_fn.(name, event, detail)
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
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

  test "notification fires again on a second down after recovery", %{mon: mon} do
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

  test "extending maintenance before expiry keeps it alive past the old deadline", %{mon: mon} do
    check = CheckFn.build("db")
    ManagedMonitor.register(mon, "db", check, 60_000)

    # Enter a SHORT maintenance, then immediately replace it with a LONG one.
    # The replaced (short) duration's real expiry timer must never act: well
    # after the old deadline the service must still be in maintenance, with no
    # :maintenance_ended fired. (The bookkeeping test below cannot catch this —
    # it never lets the replaced timer's real delay elapse.)
    ManagedMonitor.maintenance(mon, "db", 60)
    ManagedMonitor.maintenance(mon, "db", 60_000)

    Process.sleep(250)

    # The status call synchronizes: any stale expiry queued by the old timer
    # has been processed by the time it returns.
    assert {:ok, %{status: :maintenance}} = ManagedMonitor.status(mon, "db")
    assert Notifications.count_event(:maintenance_ended) == 0

    # A manual resume must also retire the pending expiry: a FRESH maintenance
    # session afterwards survives the resumed session's old deadline too.
    assert :ok = ManagedMonitor.resume(mon, "db")
    ManagedMonitor.maintenance(mon, "db", 60)
    assert :ok = ManagedMonitor.resume(mon, "db")
    ManagedMonitor.maintenance(mon, "db", 60_000)
    Process.sleep(250)

    assert {:ok, %{status: :maintenance}} = ManagedMonitor.status(mon, "db")
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

  # -------------------------------------------------------
  # Real periodic timers (no manual {:check, ...} driving)
  # -------------------------------------------------------

  # Drains check announcements already delivered by checks that ran before the
  # call that stopped them; never blocks.
  defp drain_ticks(tag) do
    receive do
      {:tick, ^tag} -> drain_ticks(tag)
    after
      0 -> :ok
    end
  end

  test "registration arms a repeating check timer that fires on its own", %{mon: mon} do
    test_pid = self()

    check = fn ->
      send(test_pid, {:tick, "auto_timer"})
      :ok
    end

    assert :ok = ManagedMonitor.register(mon, "auto_timer", check, 25)

    # The first firing comes from the timer armed at registration, and a further
    # firing proves the timer re-arms itself after every fire.
    assert_receive {:tick, "auto_timer"}, 1_000
    assert_receive {:tick, "auto_timer"}, 1_000

    assert {:ok, %{status: :up}} = ManagedMonitor.status(mon, "auto_timer")
  end

  test "paused service runs no checks yet keeps checking again after resume", %{mon: mon} do
    test_pid = self()

    check = fn ->
      send(test_pid, {:tick, "pause_timer"})
      :ok
    end

    assert :ok = ManagedMonitor.register(mon, "pause_timer", check, 25)
    assert_receive {:tick, "pause_timer"}, 1_000

    assert :ok = ManagedMonitor.pause(mon, "pause_timer")
    drain_ticks("pause_timer")

    # While paused the check function is not executed at all, across many
    # intervals' worth of time.
    refute_receive {:tick, "pause_timer"}, 250

    # Resuming returns the service to normal monitoring, and checks happen
    # again without any manual trigger.
    assert :ok = ManagedMonitor.resume(mon, "pause_timer")
    assert_receive {:tick, "pause_timer"}, 1_000
  end

  test "maintenance window ends by itself when the duration elapses" do
    test_pid = self()

    {:ok, mon} =
      ManagedMonitor.start_link(
        clock: &Clock.now/0,
        notify: fn name, event, detail -> send(test_pid, {:notified, name, event, detail}) end
      )

    on_exit(fn -> Process.exit(mon, :kill) end)

    assert :ok = ManagedMonitor.register(mon, "auto_maint", fn -> :ok end, 60_000)
    assert :ok = ManagedMonitor.maintenance(mon, "auto_maint", 25)

    # No {:maintenance_end, ...} is ever sent by the test: the window's own
    # expiry must fire the notification and return the service to its health.
    assert_receive {:notified, "auto_maint", :maintenance_ended, nil}, 1_000

    assert {:ok, %{status: :pending, maintenance_ends_at: nil}} =
             ManagedMonitor.status(mon, "auto_maint")
  end

  test "a deregistered service's timer chain cannot drive a re-registration", %{mon: mon} do
    test_pid = self()

    # Arm a SHORT chain, then deregister before it fires: the armed timer (and
    # any queued {:check, "web"}) must die with the registration.
    ManagedMonitor.register(mon, "web", fn -> :ok end, 80)
    assert :ok = ManagedMonitor.deregister(mon, "web")

    # Re-register far out of firing range. Only a leftover 80ms chain could
    # possibly run this check within the observation window.
    ManagedMonitor.register(
      mon,
      "web",
      fn ->
        send(test_pid, :stale_chain_fired)
        :ok
      end,
      60_000
    )

    refute_receive :stale_chain_fired, 400
    {:ok, info} = ManagedMonitor.status(mon, "web")
    assert info.status == :pending
  end

  test "a deregistered registration's maintenance expiry cannot end a re-registration's window",
       %{mon: mon} do
    check = CheckFn.build("web")
    ManagedMonitor.register(mon, "web", check, 60_000)

    # Arm a SHORT maintenance expiry, then deregister: the armed expiry (and
    # any queued {:maintenance_end, "web"}) must die with the registration.
    ManagedMonitor.maintenance(mon, "web", 60)
    assert :ok = ManagedMonitor.deregister(mon, "web")

    # Re-register and open a LONG window. Only the dead registration's 60ms
    # expiry could possibly end it inside the observation window.
    ManagedMonitor.register(mon, "web", check, 60_000)
    ManagedMonitor.maintenance(mon, "web", 60_000)

    Process.sleep(250)

    # The status call synchronizes: a stale expiry queued by the old timer
    # would have been processed by now — the window must still be open.
    assert {:ok, %{status: :maintenance}} = ManagedMonitor.status(mon, "web")
    assert Notifications.count_event(:maintenance_ended) == 0
  end
end
```
