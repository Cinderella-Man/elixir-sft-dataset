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
        service.status == :down && new_status != :down -> false
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
