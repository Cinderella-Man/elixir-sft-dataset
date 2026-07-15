# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

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
           notified_down: boolean()
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

        # Schedule the next check before updating state so the cadence is
        # maintained even if the check itself took a while; the fresh ref
        # replaces the fired one so deregister always cancels the live timer.
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

## New specification

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
