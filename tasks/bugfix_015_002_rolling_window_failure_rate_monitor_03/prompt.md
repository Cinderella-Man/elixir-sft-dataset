# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir GenServer module called `RateMonitor` that monitors registered services using a rolling-window failure rate instead of consecutive failure counts.

I need these functions in the public API:

- `RateMonitor.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration and a `:notify` option which is a function of the form `fn service_name, failure_rate -> ... end` that gets called when a service transitions to `:down`.

- `RateMonitor.register(server, service_name, check_func, interval_ms, opts \\ [])` which registers a service to be monitored. `check_func` is a zero-arity function that returns `:ok` or `{:error, reason}`. `interval_ms` is how often to run the check. `opts` accepts `:window_size` (number of recent checks to consider, default 5) and `:threshold` (failure rate as a float 0.0–1.0 at which the service is marked `:down`, default 0.6). Return `:ok` if registered successfully, or `{:error, :already_registered}` if a service with that name is already registered.

- `RateMonitor.status(server, service_name)` which returns the current status of a single service as `{:ok, status_info}` where `status_info` is a map containing at least `:status` (one of `:up`, `:down`, or `:pending`), `:last_check_at` (timestamp or `nil`), `:failure_rate` (float 0.0–1.0 computed from the window, or `0.0` if no checks yet), and `:checks_in_window` (integer count of checks recorded so far, up to `:window_size`). Return `{:error, :not_found}` if the service isn't registered.

- `RateMonitor.statuses(server)` which returns a map of all registered service names to their `status_info` maps.

- `RateMonitor.deregister(server, service_name)` which removes a service from monitoring and cancels its scheduled checks. Return `:ok` regardless of whether the service existed.

Each service should start in `:pending` status immediately after registration with an empty check history. The first check should be scheduled to run after `interval_ms` milliseconds using `Process.send_after`. After each check, the next one is scheduled the same way. The check result (`:ok` or `:error`) is appended to a bounded list of the last `window_size` results. The failure rate is computed as `number_of_errors / length(history)`. If the failure rate is `>= threshold` AND the history contains at least `window_size` entries, the status becomes `:down`. If the failure rate drops below the threshold, the status becomes `:up`. While fewer than `window_size` checks have been recorded, the service cannot transition to `:down` — it stays `:pending` or `:up`.

When a service transitions to `:down` (was not `:down` before), the notification function is called exactly once with `(service_name, failure_rate)`. If the service is already `:down` and stays `:down`, do not call the notification function again. If a `:down` service's failure rate drops below the threshold, it transitions back to `:up`, and a subsequent failure-rate breach should trigger the notification again.

Checks should be executed inside the GenServer process (just call the function directly). Use tagged `Process.send_after` messages so that each service's timer can be identified, for example `{:check, service_name}`. Make sure deregistering a service prevents any pending check message for that service from having an effect.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## The buggy module

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

    {:error, %{services: %{}, clock: clock, notify: notify}}
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

## Failing test report

```
22 of 22 test(s) failed:

  * test newly registered service starts in :pending status
      no match of right hand side value:
      
          {:error,
           %{
             notify: &RateMonitorTest.Notifications.record/2,
             services: %{},
             clock: &RateMonitorTest.Clock.now/0
           }}
      

  * test cannot register the same service name twice
      no match of right hand side value:
      
          {:error,
           %{
             notify: &RateMonitorTest.Notifications.record/2,
             services: %{},
             clock: &RateMonitorTest.Clock.now/0
           }}
      

  * test status returns :not_found for unregistered service
      no match of right hand side value:
      
          {:error,
           %{
             notify: &RateMonitorTest.Notifications.record/2,
             services: %{},
             clock: &RateMonitorTest.Clock.now/0
           }}
      

  * test service becomes :up after a successful check
      no match of right hand side value:
      
          {:error,
           %{
             notify: &RateMonitorTest.Notifications.record/2,
             services: %{},
             clock: &RateMonitorTest.Clock.now/0
           }}
      

  (…18 more)
```
