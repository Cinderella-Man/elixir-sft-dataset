# Fix the failing module

I asked for the following:

# Rolling-Window Failure-Rate Monitor

Implement an Elixir `GenServer` module called `RateMonitor` that supervises
registered services by running each service's health-check function on its own
periodic interval. Unlike a consecutive-failure monitor, service health is judged by
the **failure rate over a rolling window** of the most recent checks. Use only the
OTP standard library — no external dependencies — and deliver the complete module in
a single file.

## Starting the monitor

`RateMonitor.start_link(opts \\ [])` starts and links the process and returns the
usual `GenServer.on_start()` result. `opts` is a keyword list:

- `:clock` — a zero-arity function returning the current time in milliseconds, used
  to timestamp checks. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
- `:notify` — a two-arity function `notify.(service_name, failure_rate)` invoked
  when a service transitions to `:down` (rules below). Defaults to no notification.

Every public function below takes the server (pid) as its first argument.

## Registering services

`RateMonitor.register(server, service_name, check_func, interval_ms, opts \\ [])`

- `service_name` is any term and identifies the service.
- `check_func` is a zero-arity function returning `:ok` (healthy) or
  `{:error, reason}` (unhealthy).
- `interval_ms` is the number of milliseconds between that service's checks.
- `opts` is a keyword list:
  - `:window_size` — how many recent checks the rolling window holds. Defaults
    to `5`.
  - `:threshold` — the failure rate (a float in `0.0..1.0`) at or above which the
    service is marked `:down`. Defaults to `0.6`.

Returns `:ok` on success, or `{:error, :already_registered}` if a service with that
name is already registered — an existing registration is never replaced or altered
by a second `register` call.

On registration:

- The service starts in status `:pending` with an empty check history
  (`checks_in_window` is `0`, `failure_rate` is `0.0`, `last_check_at` is `nil`).
- Registration itself does not run the check. The first check is scheduled to run
  `interval_ms` milliseconds later using `Process.send_after`, and after each
  completed check the next one is scheduled the same way, so checks repeat every
  `interval_ms` indefinitely. The timer message for a service MUST be exactly
  `{:check, service_name}` — this message shape is part of the contract (see
  "Triggering a check manually" below).

## Performing a check

Each check invokes the service's `check_func` inside the server process and then
updates the service:

- `last_check_at` is set to the current `:clock` time for every completed check.
- The check's outcome (`:ok` or error) is appended to the service's history, which
  is bounded: only the most recent `window_size` outcomes are kept, so the oldest
  entry is evicted once the window is full, and `checks_in_window` never exceeds
  `window_size`.
- The failure rate is recomputed as `number_of_errors / length(history)` over the
  current window (it is `0.0` while the history is empty).
- The status is then re-evaluated:
  - **Full window** (`window_size` outcomes recorded): the service is `:down` when
    the failure rate is **greater than or equal to** the threshold — an
    exact-threshold rate counts as a breach — and `:up` otherwise.
  - **Partial window** (fewer than `window_size` outcomes): the service can never
    be `:down`. With zero errors recorded so far it is `:up`. With at least one
    error in the partial window: a `:pending` service becomes `:up` only when this
    check succeeded (otherwise it stays `:pending`), and a service that is already
    `:up` stays `:up`.
- Recovery is rate-driven, not event-driven: a `:down` service becomes `:up` only
  when enough new outcomes shift the full window's failure rate below the
  threshold — a single success is not sufficient while the window is still
  dominated by failures.

Notifications:

- When a service transitions to `:down` (it was not `:down` before), the `:notify`
  function is called exactly once as `notify.(service_name, failure_rate)`, with
  the failure rate that caused the transition.
- While a service is already `:down` and stays `:down`, `notify` is NOT called
  again.
- After a recovery to `:up`, the notification is re-armed: a later breach that
  transitions the service to `:down` again calls `notify` exactly once more.

## Triggering a check manually

Sending the server the message `{:check, service_name}` performs one check for that
service immediately — exactly the same work a timer-driven check performs. Because a
`GenServer` processes its mailbox in order, sending `{:check, service_name}` and
then calling `RateMonitor.status/2` observes the state produced by that completed
check. A `{:check, name}` message for a name that is not registered is ignored. This
documented message is how checks can be driven deterministically in tests.

## Querying

- `RateMonitor.status(server, service_name)` returns `{:ok, status_info}` for a
  registered service, or `{:error, :not_found}` otherwise. `status_info` is a map
  containing at least:
  - `:status` — one of `:pending`, `:up`, or `:down`;
  - `:last_check_at` — the `:clock` time of the most recent completed check, or
    `nil` if none yet;
  - `:failure_rate` — the current window's failure rate (a float in `0.0..1.0`,
    `0.0` with no checks yet);
  - `:checks_in_window` — how many outcomes the window currently holds (an
    integer, at most `window_size`).
- `RateMonitor.statuses(server)` returns a map of every registered service name to
  its `status_info` map.

## Deregistering — lifecycle rule (important)

`RateMonitor.deregister(server, service_name)` removes a service from monitoring
and always returns `:ok`, whether or not the service was registered. Deregistering
is final for that registration's schedule:

- After `deregister` returns, the service no longer appears in `statuses/1` and
  `status/2` returns `{:error, :not_found}`.
- The registration's scheduled checks never run again: any pending or future timer
  message for that service must have no effect — it must not run the check
  function, must not fire `notify`, and must not resurrect any state.
- The same name may be registered again afterwards; the new registration starts
  fresh in `:pending` with an empty window, and the OLD registration's leftover
  timers must not drive the new one.

## Robustness

Unexpected messages sent to the server must be ignored — they must not crash the
process or alter any service's state.

Services are independent: one service's failures never affect another service's
window, rate, or status.


Here is my current implementation, but it is failing tests:

```elixir
defmodule RateMonitor do
  @moduledoc """
  A GenServer that monitors registered services using a rolling-window failure
  rate rather than consecutive failure counts.

  Each service maintains a bounded list of recent check outcomes. When the
  failure rate (errors / total checks) in a full window meets or exceeds the
  configured threshold, the service transitions to `:down`. Recovery requires
  the rate to drop below the threshold — a single success is not sufficient
  if the window is still dominated by failures.
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
          failure_rate: float(),
          checks_in_window: non_neg_integer()
        }

  @typep service :: %{
           check_func: (-> :ok | {:error, term()}),
           interval_ms: pos_integer(),
           window_size: pos_integer(),
           threshold: float(),
           status: status(),
           last_check_at: integer() | nil,
           history: list(:ok | :error),
           notified_down: boolean()
         }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the RateMonitor GenServer.

  ## Options

    * `:clock`  – zero-arity function returning current time in milliseconds.
                  Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:name`   – passed directly to `GenServer.start_link/3` for registration.
    * `:notify` – `fn service_name, failure_rate -> any()` called once whenever
                  a service transitions to `:down`.
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

  ## Options

    * `:window_size` – number of recent checks to consider (default 5).
    * `:threshold`   – failure rate (0.0–1.0) at which service is `:down` (default 0.6).

  Returns `:ok` on success, or `{:error, :already_registered}`.
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
  Deregisters a service. Always returns `:ok`.
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
  def handle_call({:register, name, check_func, interval_ms, opts}, _from, state) do
    if Map.has_key?(state.services, name) do
      {:reply, {:error, :already_registered}, state}
    else
      window_size = Keyword.get(opts, :window_size, 5)
      threshold = Keyword.get(opts, :threshold, 0.6)

      service = %{
        check_func: check_func,
        interval_ms: interval_ms,
        window_size: window_size,
        threshold: threshold,
        status: :pending,
        last_check_at: nil,
        history: [],
        notified_down: false
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

  @impl GenServer
  def handle_info({:check, name}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        # Service was deregistered; discard stale message.
        {:noreply, state}

      {:ok, service} ->
        now = state.clock.()
        result = service.check_func.()

        {new_service, notify?} = apply_check_result(service, result, now)

        schedule_check(name, service.interval_ms)

        new_state = put_in(state.services[name], new_service)

        if notify? do
          fire_notify(state.notify, name, compute_failure_rate(new_service.history))
        end

        {:noreply, new_state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec apply_check_result(service(), :ok | {:error, term()}, integer()) ::
          {service(), boolean()}
  defp apply_check_result(service, result, now) do
    outcome =
      case result do
        :ok -> :ok
        {:error, _} -> :error
      end

    # Append to history, bounded by window_size.
    new_history =
      (service.history ++ [outcome])
      |> Enum.take(-service.window_size)

    failure_rate = compute_failure_rate(new_history)
    window_full = length(new_history) >= service.window_size

    new_status =
      cond do
        window_full && failure_rate >= service.threshold -> :down
        window_full -> :up
        # Window not yet full: if there are no errors so far, show :up;
        # otherwise stay :pending.
        failure_rate == 0.0 && length(new_history) > 0 -> :up
        true -> service.status |> maybe_upgrade_pending(outcome)
      end

    # Notification fires exactly on the transition into :down.
    notify? = new_status == :down && !service.notified_down && service.status != :down

    notified_down =
      cond do
        new_status == :down -> service.notified_down || notify?
        # When recovering from :down, reset the flag so future transitions
        # trigger a fresh notification.
        service.status == :down -> false
        true -> service.notified_down
      end

    new_service = %{
      service
      | status: new_status,
        last_check_at: now,
        history: new_history,
        notified_down: notified_down
    }

    {new_service, notify?}
  end

  # If pending and we just got an :ok, move to :up. Otherwise keep current.
  defp maybe_upgrade_pending(:pending, :ok), do: :up
  defp maybe_upgrade_pending(current, _), do: current

  @spec compute_failure_rate(list(:ok | :error)) :: float()
  defp compute_failure_rate([]), do: 0.0

  defp compute_failure_rate(history) do
    errors = Enum.count(history, &(&1 == :error))
    errors / length(history)
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
      failure_rate: compute_failure_rate(service.history),
      checks_in_window: length(service.history)
    }
  end

  @spec fire_notify((service_name(), float() -> any()) | nil, service_name(), float()) :: any()
  defp fire_notify(nil, _name, _rate), do: :ok
  defp fire_notify(notify_fn, name, rate), do: notify_fn.(name, rate)
end

```

The failure report:

```
Tests failed (1 failed, 0 errors):
  - test old registration's leftover timer never drives a re-registered service (RateMonitorTest): 

Unexpectedly received message :new_ran (which matched :new_ran)

```

Find the bug and give me the corrected complete module in a single file.
<!-- minted from logs/attempts/015_002_rolling_window_failure_rate_monitor_01_audit/attempt_0 -->
