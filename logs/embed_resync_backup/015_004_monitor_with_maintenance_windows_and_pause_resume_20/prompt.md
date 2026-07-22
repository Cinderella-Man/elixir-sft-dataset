# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `fire_notify` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Managed Monitor with Maintenance Windows and Pause/Resume

Implement an Elixir `GenServer` module called `ManagedMonitor` that supervises
registered services with periodic health checks, and adds operational controls on
top of plain up/down monitoring: individual services can be **paused** (checks
skipped) or put into a **maintenance window** (checks run, but failures are
forgiven) that expires automatically. Use only the OTP standard library — no
external dependencies — and deliver the complete module in a single file.

## Starting the monitor

`ManagedMonitor.start_link(opts \\ [])` starts and links the process and returns
the usual `GenServer.on_start()` result. `opts` is a keyword list:

- `:clock` — a zero-arity function returning the current time in milliseconds, used
  to timestamp checks and compute maintenance deadlines. Defaults to
  `fn -> System.monotonic_time(:millisecond) end`.
- `:notify` — a three-arity function `notify.(service_name, event, detail)` invoked
  on the events listed at the bottom. Defaults to no notifications.

Every public function below takes the server (pid) as its first argument.

## Registering services

`ManagedMonitor.register(server, service_name, check_func, interval_ms, max_failures \\ 3)`

- `service_name` is any term and identifies the service.
- `check_func` is a zero-arity function returning `:ok` (healthy) or
  `{:error, reason}` (unhealthy).
- `interval_ms` is the number of milliseconds between that service's checks.
- `max_failures` is the number of consecutive failures after which the service is
  marked `:down`. Defaults to `3`.

Returns `:ok` on success, or `{:error, :already_registered}` if a service with that
name is already registered — an existing registration is never replaced or altered
by a second `register` call.

On registration the service starts with health `:pending`, `consecutive_failures`
at `0`, and `last_check_at` at `nil`. Registration itself does not run a check; the
first check is scheduled `interval_ms` milliseconds later using
`Process.send_after`, and after each fired timer the next one is scheduled the same
way, so the timer keeps firing every `interval_ms` indefinitely (even while the
service is paused or in maintenance). The check-timer message MUST be exactly
`{:check, service_name}` — this message shape is part of the contract (see
"Triggering a check manually" below).

## Normal (active) checks

When the check timer fires for an active (not paused, not in-maintenance) service,
`check_func` is invoked inside the server process and the service is updated:

- `last_check_at` is set to the current `:clock` time.
- On `:ok`: the consecutive-failure counter resets to `0` and the health becomes
  `:up`.
- On `{:error, reason}`: the counter increments; the health is left unchanged while
  the counter is below `max_failures`.
- When the counter reaches `max_failures`, the health transitions to `:down` and
  `notify.(service_name, :down, reason)` fires exactly once, with the
  threshold-crossing check's reason. While already `:down` and still failing, no
  further `:down` notification fires.
- When a `:down` service's check returns `:ok`, it transitions back to `:up`,
  `notify.(service_name, :recovered, nil)` fires, the counter resets, and the
  `:down` notification is re-armed for any future run of failures.

## Pausing and resuming

- `ManagedMonitor.pause(server, service_name)` pauses monitoring. While paused, the
  check timers keep firing on schedule but `check_func` is NOT executed and nothing
  about the service changes; its reported `:status` is `:paused` while its health
  (`:pending`, `:up`, or `:down`) and failure counter are preserved unchanged
  underneath. Returns `:ok`, or `{:error, :not_found}` for an unknown service.
- `ManagedMonitor.resume(server, service_name)` resumes a service that is currently
  paused OR in maintenance; its reported status reverts to the preserved health,
  and the failure counter is preserved. Resuming a service that is neither paused
  nor in maintenance returns `{:error, :not_paused}`; an unknown service returns
  `{:error, :not_found}`. Resuming out of a maintenance window retires that
  window's pending expiry — it never fires afterwards (see the lifecycle rule
  below).

## Maintenance windows

`ManagedMonitor.maintenance(server, service_name, duration_ms)` puts a service into
maintenance mode for `duration_ms` milliseconds and returns `:ok` (or
`{:error, :not_found}`). `notify.(service_name, :maintenance_started, duration_ms)`
fires each time maintenance is entered (including re-entry).

During maintenance:

- The reported `:status` is `:maintenance`, and `:maintenance_ends_at` in the
  status map is the `:clock` time at which the window will expire
  (`clock_at_entry + duration_ms`).
- Check timers keep firing and `check_func` IS executed with `last_check_at`
  updated, but failures are forgiven: they do NOT increment the failure counter and
  can never cause a `:down` transition. Successes still reset the counter and set
  the underlying health to `:up`.

The window expires by itself: the expiry is tracked with a
`Process.send_after(self(), {:maintenance_end, service_name}, duration_ms)` timer.
On expiry, `notify.(service_name, :maintenance_ended, nil)` fires and the service
returns to normal monitoring, its reported status reverting to its current health.

### Replacing a maintenance window — lifecycle rule (important)

Calling `maintenance/3` while the service is already in maintenance REPLACES the
window: the duration restarts from now, `:maintenance_ends_at` reflects the new
deadline, and `:maintenance_started` fires again. The replaced window's expiry is
retired and must never act — in particular, EXTENDING a window (a short duration
replaced by a longer one) must keep the service in maintenance past the old
deadline, with no early exit and no spurious `:maintenance_ended`. The same
holds after a manual `resume/2`: a retired window's expiry never affects any
later maintenance session. A `{:maintenance_end, name}` message for a service
that is missing or no longer in maintenance is ignored.

## Triggering a check manually

Sending the server the message `{:check, service_name}` performs one check cycle
for that service immediately — with exactly the mode-dependent behavior above
(skipped while paused, forgiven while in maintenance, normal otherwise). Because a
`GenServer` processes its mailbox in order, sending `{:check, service_name}` and
then calling `ManagedMonitor.status/2` observes the state produced by that
completed cycle. A `{:check, name}` message for an unregistered name is ignored.
This documented message is how checks can be driven deterministically in tests.

## Querying

- `ManagedMonitor.status(server, service_name)` returns `{:ok, status_info}` for a
  registered service, or `{:error, :not_found}` otherwise. `status_info` is a map
  containing at least:
  - `:status` — `:pending`, `:up`, or `:down` for an active service; `:paused`
    while paused; `:maintenance` while in a maintenance window;
  - `:last_check_at` — the `:clock` time of the most recent executed check, or
    `nil` if none yet;
  - `:consecutive_failures` — the current run of uninterrupted counted failures;
  - `:maintenance_ends_at` — the current window's expiry time, or `nil` when not
    in maintenance.
- `ManagedMonitor.statuses(server)` returns a map of every registered service name
  to its `status_info` map.

## Deregistering — lifecycle rule (important)

`ManagedMonitor.deregister(server, service_name)` removes a service from
monitoring and always returns `:ok`, whether or not the service was registered
(and regardless of its mode). After `deregister` returns, the service no longer
appears in `statuses/1`, `status/2` returns `{:error, :not_found}`, and none of
the registration's scheduled messages may have any effect: a pending or future
`{:check, ...}` or `{:maintenance_end, ...}` for it must not run a check, must
not fire any notification, and must not resurrect any state. The same name may
be registered again afterwards, starting fresh in `:pending`, and the old
registration's leftover timers must not drive the new one.

## Notification events (summary)

- `notify.(name, :down, reason)` — health transition to `:down`, exactly once per
  down-transition.
- `notify.(name, :recovered, nil)` — health transition from `:down` to `:up`.
- `notify.(name, :maintenance_started, duration_ms)` — every entry (or re-entry)
  into maintenance.
- `notify.(name, :maintenance_ended, nil)` — a maintenance window expiring on its
  own (a manual `resume/2` does not fire it).

## Robustness

Unexpected messages sent to the server must be ignored — they must not crash the
process or alter any service's state.

Services are independent: one service's failures, pauses, or maintenance never
affect another service's health, counters, or windows.

## The module with `fire_notify` missing

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
        maintenance_ends_at: nil,
        maintenance_timer: nil
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

  defp fire_notify(nil, _name, _event, _detail) do
    # TODO
  end
end
```

Give me only the complete implementation of `fire_notify` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
