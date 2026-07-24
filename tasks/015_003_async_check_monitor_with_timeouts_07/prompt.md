# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `status`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

# Async Check Monitor with Timeouts

Implement an Elixir `GenServer` module called `AsyncMonitor` that supervises
registered services by running each service's health check **asynchronously in a
spawned Task** with a per-service timeout, so a slow or hung check can never block
the monitor or other services. Use only the OTP standard library — no external
dependencies — and deliver the complete module in a single file.

## Starting the monitor

`AsyncMonitor.start_link(opts \\ [])` starts and links the process and returns the
usual `GenServer.on_start()` result. `opts` is a keyword list:

- `:clock` — a zero-arity function returning the current time in milliseconds, used
  to timestamp checks. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
- `:notify` — a two-arity function `notify.(service_name, reason)` invoked when a
  service transitions to `:down` (rules below). Defaults to no notification.

Every public function below takes the server (pid) as its first argument.

## Registering services

`AsyncMonitor.register(server, service_name, check_func, interval_ms, opts \\ [])`

- `service_name` is any term and identifies the service.
- `check_func` is a zero-arity function returning `:ok` (healthy) or
  `{:error, reason}` (unhealthy).
- `interval_ms` is the number of milliseconds between that service's checks.
- `opts` is a keyword list:
  - `:max_failures` — consecutive failures (including timeouts) before the service
    is marked `:down`. Defaults to `3`.
  - `:timeout_ms` — the maximum time a single check Task may run. Defaults to
    `5000`.

Returns `:ok` on success, or `{:error, :already_registered}` if a service with that
name is already registered — an existing registration is never replaced or altered
by a second `register` call.

On registration the service starts in status `:pending`, with `consecutive_failures`
at `0`, `last_check_at` at `nil`, and no check in flight. Registration itself does
not run a check; the first check is scheduled `interval_ms` milliseconds later.

## The check protocol (part of the contract)

The message shapes below are the documented protocol — tests drive and observe the
monitor through them, so implement them exactly:

- Scheduling: each service's next check is armed with
  `Process.send_after(self(), {:schedule_check, service_name}, interval_ms)`.
  Receiving `{:schedule_check, service_name}` starts one check for that service:
  the GenServer spawns a `Task` executing `check_func`, monitors it, and stores the
  Task's reference as the service's currently expected reference
  (`check_in_flight` becomes `true`).
- Completion: the Task sends `{:check_result, service_name, task_ref, result}`
  back to the GenServer when the check function returns.
- Timeout: at spawn time the GenServer also arms
  `Process.send_after(self(), {:check_timeout, service_name, task_ref}, timeout_ms)`.
  If the timeout message arrives while that same Task is still the expected
  in-flight check, the GenServer kills the Task with `Process.exit(task_pid, :kill)`
  and treats the check as a failure with reason `:timeout`.
- Staleness: a `{:check_result, ...}` or `{:check_timeout, ...}` whose `task_ref`
  does not match the service's currently expected reference — because the timeout
  already fired, the result already arrived, or the service was deregistered or
  re-registered in between — is silently discarded and changes nothing.
- After a check concludes (success, failure, or timeout), `check_in_flight` returns
  to `false` and the next check is scheduled `interval_ms` later.
- Only one check Task is ever in flight per service; `{:schedule_check, name}` for
  an unregistered name is ignored.

Because a `GenServer` processes its mailbox in order, sending the server
`{:schedule_check, service_name}` and then making a synchronous call (such as
`status/2`) is the documented deterministic way to drive a check in tests.

## Check outcomes

- `last_check_at` is set to the current `:clock` time when a check concludes.
- On `:ok`: the consecutive-failure counter resets to `0` and the status becomes
  `:up`.
- On `{:error, reason}` or a timeout (reason `:timeout`): the counter increments;
  the status is left unchanged while the counter is below `max_failures`.
- When the counter reaches `max_failures`, the status transitions to `:down` and
  `notify.(service_name, reason)` is called exactly once, with the reason from the
  latest (threshold-crossing) failure.
- While already `:down` and still failing, `notify` is NOT called again.
- If a `:down` service's check returns `:ok`, it transitions back to `:up`, the
  counter resets, and the notification is re-armed: a later run to `max_failures`
  calls `notify` exactly once more, with the new failure's reason.

## Querying

- `AsyncMonitor.status(server, service_name)` returns `{:ok, status_info}` for a
  registered service, or `{:error, :not_found}` otherwise. `status_info` is a map
  containing at least:
  - `:status` — one of `:pending`, `:up`, or `:down`;
  - `:last_check_at` — the `:clock` time of the most recent concluded check, or
    `nil` if none yet;
  - `:consecutive_failures` — the current run of uninterrupted failures;
  - `:check_in_flight` — a boolean, `true` while a check Task is currently
    running for the service.
- `AsyncMonitor.statuses(server)` returns a map of every registered service name
  to its `status_info` map.

## Deregistering — lifecycle rule (important)

`AsyncMonitor.deregister(server, service_name)` removes a service from monitoring
and always returns `:ok`, whether or not the service was registered. Deregistering
is final for that registration:

- After `deregister` returns, the service no longer appears in `statuses/1` and
  `status/2` returns `{:error, :not_found}`.
- Any in-flight check Task for the service is shut down, and the registration's
  scheduled messages never have an effect again: a pending or future
  `{:schedule_check, ...}`, `{:check_result, ...}`, or `{:check_timeout, ...}`
  belonging to it must not run a check, must not fire `notify`, and must not
  resurrect any state.
- The same name may be registered again afterwards; the new registration starts
  fresh in `:pending`, and the OLD registration's leftover messages must not drive
  the new one (the reference match above guarantees this).

## Robustness

Unexpected messages sent to the server must be ignored — they must not crash the
process or alter any service's state.

Services are independent: concurrent checks for different services run in separate
Tasks, and one service's failures, timeouts, or `:down` status never affect
another's counters or status. The GenServer itself must remain responsive while
check Tasks execute.

## The module with `status` missing

```elixir
defmodule AsyncMonitor do
  @moduledoc """
  A GenServer that monitors registered services via periodic health checks
  where each check runs asynchronously in a spawned Task with a configurable
  timeout.

  Unlike a synchronous monitor, this design prevents slow check functions from
  blocking the GenServer. Each check is spawned as a separate process, and a
  timeout timer ensures the GenServer isn't stuck waiting indefinitely.
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
          consecutive_failures: non_neg_integer(),
          check_in_flight: boolean()
        }

  @typep service :: %{
           check_func: (-> :ok | {:error, term()}),
           interval_ms: pos_integer(),
           max_failures: pos_integer(),
           timeout_ms: pos_integer(),
           status: status(),
           last_check_at: integer() | nil,
           consecutive_failures: non_neg_integer(),
           notified_down: boolean(),
           task_ref: reference() | nil,
           task_pid: pid() | nil
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

  @doc """
  Registers `service_name` with an async `check_func`. Returns `:ok`, or
  `{:error, :already_registered}` if `service_name` is already registered.
  """
  @spec register(
          GenServer.server(),
          service_name(),
          (-> :ok | {:error, term()}),
          pos_integer(),
          keyword()
        ) :: :ok | {:error, :already_registered}
  def register(server, service_name, check_func, interval_ms, opts \\ []) do
    GenServer.call(server, {:register, service_name, check_func, interval_ms, opts})
  end

  @spec status(GenServer.server(), service_name()) ::
          {:ok, status_info()} | {:error, :not_found}

  def status(server, service_name) do
    # TODO
  end

  @spec statuses(GenServer.server()) :: %{service_name() => status_info()}
  def statuses(server) do
    GenServer.call(server, :statuses)
  end

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
  def handle_call({:register, name, check_func, interval_ms, opts}, _from, state) do
    if Map.has_key?(state.services, name) do
      {:reply, {:error, :already_registered}, state}
    else
      max_failures = Keyword.get(opts, :max_failures, 3)
      timeout_ms = Keyword.get(opts, :timeout_ms, 5_000)

      service = %{
        check_func: check_func,
        interval_ms: interval_ms,
        max_failures: max_failures,
        timeout_ms: timeout_ms,
        status: :pending,
        last_check_at: nil,
        consecutive_failures: 0,
        notified_down: false,
        task_ref: nil,
        task_pid: nil
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
    case Map.fetch(state.services, name) do
      {:ok, service} ->
        # Kill any in-flight task.
        if service.task_pid do
          Process.exit(service.task_pid, :kill)
        end

        {:reply, :ok, %{state | services: Map.delete(state.services, name)}}

      :error ->
        {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_info({:schedule_check, name}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:noreply, state}

      {:ok, service} ->
        # Spawn a Task to run the check function.
        gen_server = self()
        ref = make_ref()

        {:ok, pid} =
          Task.start(fn ->
            result =
              try do
                service.check_func.()
              rescue
                e -> {:error, {:exception, Exception.message(e)}}
              catch
                kind, value -> {:error, {kind, value}}
              end

            send(gen_server, {:check_result, name, ref, result})
          end)

        # Monitor the task so we know if it crashes.
        Process.monitor(pid)

        # Schedule a timeout message.
        Process.send_after(self(), {:check_timeout, name, ref}, service.timeout_ms)

        new_service = %{service | task_ref: ref, task_pid: pid}
        {:noreply, put_in(state.services[name], new_service)}
    end
  end

  def handle_info({:check_result, name, ref, result}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:noreply, state}

      {:ok, %{task_ref: ^ref} = service} ->
        now = state.clock.()
        {new_service, notify?} = apply_check_result(service, result, now)
        new_service = %{new_service | task_ref: nil, task_pid: nil}

        schedule_check(name, service.interval_ms)

        new_state = put_in(state.services[name], new_service)

        if notify? do
          {:error, reason} = result
          fire_notify(state.notify, name, reason)
        end

        {:noreply, new_state}

      {:ok, _service} ->
        # Stale ref — result from an old task. Discard.
        {:noreply, state}
    end
  end

  def handle_info({:check_timeout, name, ref}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:noreply, state}

      {:ok, %{task_ref: ^ref, task_pid: pid} = service} ->
        # Kill the timed-out task.
        if pid, do: Process.exit(pid, :kill)

        now = state.clock.()
        {new_service, notify?} = apply_check_result(service, {:error, :timeout}, now)
        new_service = %{new_service | task_ref: nil, task_pid: nil}

        schedule_check(name, service.interval_ms)

        new_state = put_in(state.services[name], new_service)

        if notify? do
          fire_notify(state.notify, name, :timeout)
        end

        {:noreply, new_state}

      {:ok, _service} ->
        # Stale ref — timeout for an already-completed or replaced task.
        {:noreply, state}
    end
  end

  # Handle DOWN messages from monitored tasks — just ignore them.
  # We handle lifecycle via check_result/check_timeout.
  def handle_info({:DOWN, _monitor_ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec apply_check_result(service(), :ok | {:error, term()}, integer()) ::
          {service(), boolean()}
  defp apply_check_result(service, :ok, now) do
    new_service = %{
      service
      | status: :up,
        last_check_at: now,
        consecutive_failures: 0,
        notified_down: false
    }

    {new_service, false}
  end

  defp apply_check_result(service, {:error, _reason}, now) do
    new_failures = service.consecutive_failures + 1
    threshold_reached = new_failures >= service.max_failures

    notify? = threshold_reached && !service.notified_down

    new_status = if threshold_reached, do: :down, else: service.status

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
    Process.send_after(self(), {:schedule_check, name}, interval_ms)
  end

  @spec to_status_info(service()) :: status_info()
  defp to_status_info(service) do
    %{
      status: service.status,
      last_check_at: service.last_check_at,
      consecutive_failures: service.consecutive_failures,
      check_in_flight: service.task_ref != nil
    }
  end

  @spec fire_notify((service_name(), term() -> any()) | nil, service_name(), term()) :: any()
  defp fire_notify(nil, _name, _reason), do: :ok
  defp fire_notify(notify_fn, name, reason), do: notify_fn.(name, reason)
end
```

Output only `status` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
