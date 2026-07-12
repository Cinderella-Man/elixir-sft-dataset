# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir GenServer module called `ManagedMonitor` that monitors registered services via periodic heartbeat checks with support for maintenance windows and manual pause/resume of individual services.

I need these functions in the public API:

- `ManagedMonitor.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration and a `:notify` option which is a function of the form `fn service_name, event, detail -> ... end` that gets called on status transitions (see below).

- `ManagedMonitor.register(server, service_name, check_func, interval_ms, max_failures \\ 3)` which registers a service to be monitored. `check_func` is a zero-arity function that returns `:ok` or `{:error, reason}`. `interval_ms` is how often to run the check. `max_failures` is how many consecutive failures before the service is marked `:down`. Return `:ok` if registered successfully, or `{:error, :already_registered}` if a service with that name is already registered.

- `ManagedMonitor.status(server, service_name)` which returns the current status of a single service as `{:ok, status_info}` where `status_info` is a map containing at least `:status` (one of `:up`, `:down`, `:pending`, `:paused`, or `:maintenance`), `:last_check_at` (timestamp or `nil`), `:consecutive_failures` (integer), and `:maintenance_ends_at` (timestamp or `nil`). Return `{:error, :not_found}` if the service isn't registered.

- `ManagedMonitor.statuses(server)` which returns a map of all registered service names to their `status_info` maps.

- `ManagedMonitor.deregister(server, service_name)` which removes a service from monitoring and cancels its scheduled checks. Return `:ok` regardless of whether the service existed.

- `ManagedMonitor.pause(server, service_name)` which pauses monitoring of a service. While paused, scheduled check timers continue to fire but the check function is NOT executed — the service stays in its pre-pause health state internally but its reported status becomes `:paused`. Return `:ok` or `{:error, :not_found}`.

- `ManagedMonitor.resume(server, service_name)` which resumes a paused service. The reported status reverts to whatever the health state was before pausing (`:pending`, `:up`, or `:down`). The consecutive failure counter is preserved. Return `:ok`, `{:error, :not_found}`, or `{:error, :not_paused}` if the service isn't currently paused or in maintenance.

- `ManagedMonitor.maintenance(server, service_name, duration_ms)` which puts a service into maintenance mode for `duration_ms` milliseconds. During maintenance, check timers fire and the check function IS executed, but failures do NOT increment the consecutive failure counter and do NOT trigger `:down` transitions. Successes still reset the failure counter and update the health state to `:up`. The reported status is `:maintenance`. When the duration expires (tracked via `Process.send_after` with a `{:maintenance_end, service_name}` message), the service automatically resumes normal monitoring — its reported status reverts to its current health state. Return `:ok` or `{:error, :not_found}`. If already in maintenance, the duration is replaced (restarted).

The notification function `notify(service_name, event, detail)` should be called for these events:
- `(:down, reason)` — when a service transitions to `:down` (same semantics as before: exactly once per down-transition, not while already `:down`, re-arms on recovery).
- `(:recovered, nil)` — when a service transitions from `:down` to `:up`.
- `(:maintenance_started, duration_ms)` — when maintenance mode begins.
- `(:maintenance_ended, nil)` — when maintenance mode expires.

Checks should be executed inside the GenServer process (just call the function directly). Use tagged `Process.send_after` messages for scheduling, e.g. `{:check, service_name}`. Make sure deregistering a service prevents any pending check or maintenance-end message from having an effect. When a paused service is deregistered, no special handling is needed beyond removing it. When a maintenance service is deregistered, the pending maintenance-end timer is effectively orphaned and discarded when it fires for a missing service.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## The buggy module

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
           maintenance_ends_at: integer() | nil
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

  @doc "Registers `service_name` with `check_func` every `interval_ms`. Returns `:ok`."
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
        maintenance_ends_at: nil
      }

      schedule_check(name, interval_ms)

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

        Process.send_after(self(), {:maintenance_end, name}, duration_ms)

        new_service = %{service | mode: :maintenance, maintenance_ends_at: ends_at}
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
        # Paused: skip the check but keep scheduling.
        schedule_check(name, service.interval_ms)
        {:noreply, state}

      {:ok, %{mode: :maintenance} = service} ->
        now = state.clock.()
        result = service.check_func.()

        new_service = apply_maintenance_check(service, result, now)

        schedule_check(name, service.interval_ms)

        {:noreply, put_in(state.services[name], new_service)}

      {:ok, service} ->
        now = state.clock.()
        result = service.check_func.()

        {new_service, events} = apply_active_check(service, result, now)

        schedule_check(name, service.interval_ms)

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
        new_service = %{service | mode: :active, maintenance_ends_at: nil}

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
    threshold_reached = new_failures > service.max_failures

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
  defp schedule_check(name, interval_ms) do
    Process.send_after(self(), {:check, name}, interval_ms)
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

## Failing test report

```
6 of 29 test(s) failed:

  * test service goes :down after max_failures consecutive failures
      
      
      match (=) failed
      code:  assert {:ok, %{status: :down, consecutive_failures: 3}} = ManagedMonitor.status(mon, "db")
      left:  {:ok, %{status: :down, consecutive_failures: 3}}
      right: {:ok, %{status: :pending, last_check_at: 3000, consecutive_failures: 3, maintenance_ends_at: nil}}
      

  * test notification fires exactly once on transition to :down
      
      
      Assertion with == failed
      code:  assert Notifications.count_event(:down) == 1
      left:  0
      right: 1
      

  * test a :down service recovers to :up when check succeeds
      
      
      match (=) failed
      code:  assert {:ok, %{status: :down}} = ManagedMonitor.status(mon, "api")
      left:  {:ok, %{status: :down}}
      right: {:ok, %{status: :pending, last_check_at: 3000, consecutive_failures: 3, maintenance_ends_at: nil}}
      

  * test recovery notification fires when service goes from :down to :up
      
      
      Assertion with == failed
      code:  assert Notifications.count_event(:recovered) == 1
      left:  0
      right: 1
      

  (…2 more)
```
