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
    # Removing the service from the map is sufficient: any in-flight
    # {:check, name} message will hit the :error branch in handle_info
    # and be silently discarded.
    {:reply, :ok, %{state | services: Map.delete(state.services, name)}}
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
        # maintained even if the check itself took a while.
        schedule_check(name, service.interval_ms)

        new_state = put_in(state.services[name], new_service)

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
