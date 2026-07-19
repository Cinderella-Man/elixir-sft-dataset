# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `start_link` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Heartbeat Monitor

Implement an Elixir `GenServer` module called `Monitor` that supervises registered
services by running each service's health-check function on its own periodic
interval and tracking a per-service status. Use only the OTP standard library — no
external dependencies — and deliver the complete module in a single file.

## Starting the monitor

`Monitor.start_link(opts \\ [])` starts and links the process and returns the usual
`GenServer.on_start()` result. `opts` is a keyword list:

- `:clock` — a zero-arity function returning the current time in milliseconds, used
  to timestamp checks. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
- `:notify` — a two-arity function `notify.(service_name, reason)` invoked when a
  service transitions to `:down` (the exact rules are below). Defaults to no
  notification.

Every public function below takes the server (pid) as its first argument.

## Registering services

`Monitor.register(server, service_name, check_func, interval_ms, max_failures \\ 3)`

- `service_name` is any term and identifies the service.
- `check_func` is a zero-arity function that, when invoked, returns either `:ok`
  (healthy) or `{:error, reason}` (unhealthy), where `reason` is any term.
- `interval_ms` is the number of milliseconds between that service's checks.
- `max_failures` is the number of consecutive failures after which the service is
  marked `:down`. It defaults to `3`.

Returns `:ok` on success, or `{:error, :already_registered}` if a service with that
name is already registered — an existing registration is never replaced or altered
by a second `register` call.

On registration:

- The service starts in status `:pending`, with `consecutive_failures` at `0` and
  `last_check_at` set to `nil`.
- Registration itself does not run the check. The first check is scheduled to run
  `interval_ms` milliseconds later using `Process.send_after`, and after each
  completed check the next one is scheduled the same way, so checks repeat every
  `interval_ms` indefinitely. The timer message for a service MUST be exactly
  `{:check, service_name}` — this message shape is part of the contract (see
  "Triggering a check manually" below).

## Performing a check

Each check invokes the service's `check_func` inside the server process (call the
function directly) and then updates the service:

- `last_check_at` is set to the current `:clock` time for every completed check,
  successful or not.
- If the result is `:ok`: the consecutive-failure counter resets to `0` and the
  status becomes `:up`.
- If the result is `{:error, reason}`: the consecutive-failure counter increments
  by one. The status is left unchanged while the counter is below `max_failures`
  (a `:pending` service stays `:pending`, an `:up` service stays `:up`).
- When the counter reaches `max_failures`, the status transitions to `:down` and
  the `:notify` function is called exactly once as `notify.(service_name, reason)`,
  where `reason` comes from the latest (threshold-crossing) failing check.
- While a service is already `:down` and keeps failing, `notify` is NOT called
  again, and the counter keeps counting.
- If a `:down` service's check returns `:ok`, it transitions back to `:up`, the
  counter resets to `0`, and the notification is re-armed: a later run of
  `max_failures` consecutive failures transitions it to `:down` again and calls
  `notify` exactly once more, with the new failure's reason.

## Triggering a check manually

Sending the server the message `{:check, service_name}` performs one check for that
service immediately — exactly the same work a timer-driven check performs (invoking
the check function, updating `last_check_at`, the counter, the status, and firing
`notify` per the rules above). Because a `GenServer` processes its mailbox in order,
sending `{:check, service_name}` and then calling `Monitor.status/2` observes the
state produced by that completed check. A `{:check, name}` message for a name that
is not registered is ignored. This documented message is how checks can be driven
deterministically in tests.

## Querying

- `Monitor.status(server, service_name)` returns `{:ok, status_info}` for a
  registered service, or `{:error, :not_found}` otherwise. `status_info` is a map
  containing at least:
  - `:status` — one of `:pending`, `:up`, or `:down`;
  - `:last_check_at` — the `:clock` time of the most recent completed check, or
    `nil` if no check has completed yet;
  - `:consecutive_failures` — the current run of uninterrupted failures.
- `Monitor.statuses(server)` returns a map of every registered service name to its
  `status_info` map.

## Deregistering — lifecycle rule (important)

`Monitor.deregister(server, service_name)` removes a service from monitoring and
always returns `:ok`, whether or not the service was registered. Deregistering is
final for that registration's schedule:

- After `deregister` returns, the service no longer appears in `statuses/1` and
  `status/2` returns `{:error, :not_found}`.
- The registration's scheduled checks never run again: any pending or future timer
  message for that service must have no effect — it must not run the check
  function, must not fire `notify`, and must not resurrect any state.
- The same name may be registered again afterwards; the new registration starts
  fresh in `:pending`, and the OLD registration's leftover timers must not drive
  the new one (no early checks, no doubled cadence, no stale failure counting).

## Robustness

Unexpected messages sent to the server must be ignored — they must not crash the
process or alter any service's state.

Services are independent: one service failing (or going `:down`) never affects
another service's status or counters.

## The module with `start_link` missing

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

  def start_link(opts \\ []) do
    # TODO
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

Give me only the complete implementation of `start_link` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
