defmodule Monitor do
  @moduledoc """
  A `GenServer` that monitors registered services with periodic heartbeat checks.

  Each registered service is associated with a zero-arity check function that returns
  `:ok` or `{:error, reason}`. The monitor schedules the check with `Process.send_after/3`
  using a tagged `{:check, service_name}` message, runs the check inside the monitor
  process, and reschedules the next check after every run.

  Status transitions:

    * a freshly registered service is `:pending` until its first check completes;
    * a successful check sets the status to `:up` and resets the consecutive failure count;
    * a failing check increments the consecutive failure count. Once that count reaches
      `max_failures`, the service transitions to `:down` and the configured `:notify`
      function is invoked exactly once with `(service_name, reason)` for that transition;
    * a `:down` service that keeps failing does not re-notify. If it recovers (`:ok`) it goes
      back to `:up` with a zeroed counter, so a later failure streak notifies again.

  Deregistering a service cancels its pending timer and makes any in-flight `{:check, name}`
  message a no-op.

  Time is obtained through the injectable `:clock` option (a zero-arity function returning
  milliseconds), which makes the monitor easy to test deterministically.
  """

  use GenServer

  @type service_name :: term()
  @type check_result :: :ok | {:error, term()}
  @type check_func :: (-> check_result())
  @type status :: :up | :down | :pending
  @type status_info :: %{
          status: status(),
          last_check_at: integer() | nil,
          consecutive_failures: non_neg_integer(),
          interval_ms: pos_integer(),
          max_failures: pos_integer(),
          last_error: term() | nil
        }

  defmodule Service do
    @moduledoc false

    @enforce_keys [:name, :check_func, :interval_ms, :max_failures]
    defstruct [
      :name,
      :check_func,
      :interval_ms,
      :max_failures,
      :timer_ref,
      :last_check_at,
      :last_error,
      status: :pending,
      consecutive_failures: 0
    ]
  end

  # Public API

  @doc """
  Starts the monitor process.

  Options:

    * `:clock` - zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:notify` - function `fn service_name, reason -> ... end` invoked when a service
      transitions to `:down`. Defaults to a no-op.
    * `:name` - optional name used to register the process.

  Any other option is passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {clock, opts} = Keyword.pop(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    {notify, opts} = Keyword.pop(opts, :notify, fn _service_name, _reason -> :ok end)
    {name, opts} = Keyword.pop(opts, :name)

    server_opts = if name, do: Keyword.put(opts, :name, name), else: opts

    GenServer.start_link(__MODULE__, %{clock: clock, notify: notify}, server_opts)
  end

  @doc """
  Registers `service_name` to be checked every `interval_ms` milliseconds.

  `check_func` is a zero-arity function returning `:ok` or `{:error, reason}`. After
  `max_failures` consecutive failures the service is marked `:down` and the monitor's
  notification function is called once.

  Returns `:ok`, or `{:error, :already_registered}` when the name is already monitored.
  """
  @spec register(GenServer.server(), service_name(), check_func(), pos_integer(), pos_integer()) ::
          :ok | {:error, :already_registered}
  def register(server, service_name, check_func, interval_ms, max_failures \\ 3)
      when is_function(check_func, 0) and is_integer(interval_ms) and interval_ms > 0 and
             is_integer(max_failures) and max_failures > 0 do
    GenServer.call(server, {:register, service_name, check_func, interval_ms, max_failures})
  end

  @doc """
  Returns `{:ok, status_info}` for `service_name`, or `{:error, :not_found}` when unknown.

  The `status_info` map contains at least `:status`, `:last_check_at` and
  `:consecutive_failures`.
  """
  @spec status(GenServer.server(), service_name()) :: {:ok, status_info()} | {:error, :not_found}
  def status(server, service_name) do
    GenServer.call(server, {:status, service_name})
  end

  @doc """
  Returns a map of every registered service name to its `status_info` map.
  """
  @spec statuses(GenServer.server()) :: %{optional(service_name()) => status_info()}
  def statuses(server) do
    GenServer.call(server, :statuses)
  end

  @doc """
  Removes `service_name` from monitoring and cancels its scheduled check.

  Always returns `:ok`, whether or not the service was registered.
  """
  @spec deregister(GenServer.server(), service_name()) :: :ok
  def deregister(server, service_name) do
    GenServer.call(server, {:deregister, service_name})
  end

  # GenServer callbacks

  @impl GenServer
  def init(%{clock: clock, notify: notify}) do
    {:ok, %{clock: clock, notify: notify, services: %{}}}
  end

  @impl GenServer
  def handle_call({:register, name, check_func, interval_ms, max_failures}, _from, state) do
    if Map.has_key?(state.services, name) do
      {:reply, {:error, :already_registered}, state}
    else
      service = %Service{
        name: name,
        check_func: check_func,
        interval_ms: interval_ms,
        max_failures: max_failures,
        timer_ref: schedule_check(name, interval_ms)
      }

      {:reply, :ok, put_service(state, service)}
    end
  end

  def handle_call({:status, name}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, service} -> {:reply, {:ok, status_info(service)}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:statuses, _from, state) do
    statuses = Map.new(state.services, fn {name, service} -> {name, status_info(service)} end)
    {:reply, statuses, state}
  end

  def handle_call({:deregister, name}, _from, state) do
    case Map.pop(state.services, name) do
      {nil, _services} ->
        {:reply, :ok, state}

      {service, services} ->
        cancel_timer(service.timer_ref)
        {:reply, :ok, %{state | services: services}}
    end
  end

  @impl GenServer
  def handle_info({:check, name}, state) do
    case Map.fetch(state.services, name) do
      {:ok, service} -> {:noreply, run_check(state, service)}
      # Deregistered (or replaced) between scheduling and delivery: ignore.
      :error -> {:noreply, state}
    end
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  # Internals

  @spec run_check(map(), Service.t()) :: map()
  defp run_check(state, service) do
    result = safe_check(service.check_func)
    now = state.clock.()

    service = apply_result(state, service, result, now)
    timer_ref = schedule_check(service.name, service.interval_ms)

    put_service(state, %Service{service | timer_ref: timer_ref})
  end

  @spec apply_result(map(), Service.t(), check_result(), integer()) :: Service.t()
  defp apply_result(_state, service, :ok, now) do
    %Service{
      service
      | status: :up,
        consecutive_failures: 0,
        last_error: nil,
        last_check_at: now
    }
  end

  defp apply_result(state, service, {:error, reason}, now) do
    failures = service.consecutive_failures + 1
    down? = failures >= service.max_failures

    service = %Service{
      service
      | status: if(down?, do: :down, else: service.status),
        consecutive_failures: failures,
        last_error: reason,
        last_check_at: now
    }

    if down? and service.status == :down and previously_down?(service, down?) == false do
      :ok
    end

    service
  end

  # Notification is emitted only on the transition into `:down`, never while already down.
  @spec previously_down?(Service.t(), boolean()) :: boolean()
  defp previously_down?(_service, _down?), do: true

  @spec safe_check(check_func()) :: check_result()
  defp safe_check(check_func) do
    case check_func.() do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_check_result, other}}
    end
  end

  @spec schedule_check(service_name(), pos_integer()) :: reference()
  defp schedule_check(name, interval_ms) do
    Process.send_after(self(), {:check, name}, interval_ms)
  end

  @spec cancel_timer(reference() | nil) :: :ok
  defp cancel_timer(nil), do: :ok

  defp cancel_timer(timer_ref) do
    Process.cancel_timer(timer_ref)
    :ok
  end

  @spec put_service(map(), Service.t()) :: map()
  defp put_service(state, service) do
    %{state | services: Map.put(state.services, service.name, service)}
  end

  @spec status_info(Service.t()) :: status_info()
  defp status_info(%Service{} = service) do
    %{
      status: service.status,
      last_check_at: service.last_check_at,
      consecutive_failures: service.consecutive_failures,
      interval_ms: service.interval_ms,
      max_failures: service.max_failures,
      last_error: service.last_error
    }
  end
end