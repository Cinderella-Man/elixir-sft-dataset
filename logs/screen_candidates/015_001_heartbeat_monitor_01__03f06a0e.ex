defmodule Monitor do
  @moduledoc """
  A `GenServer` that supervises registered services by periodically running each
  service's health-check function on its own interval and tracking per-service status.

  Each registered service has:

    * a zero-arity check function returning `:ok` or `{:error, reason}`;
    * an interval in milliseconds between checks;
    * a `max_failures` threshold after which the service is marked `:down`.

  Checks are driven by `Process.send_after/3` timer messages of the exact shape
  `{:check, service_name}`. That message is part of the public contract: sending it
  to the server performs one check immediately, which makes tests deterministic.

  Deregistration is final for a registration's schedule — leftover timers from a
  removed registration are recognised and discarded, so they can neither run the old
  check function nor perturb a later registration under the same name.
  """

  use GenServer

  @default_max_failures 3

  defstruct services: %{}, clock: nil, notify: nil, next_epoch: 0

  @typedoc "Public status information for a single service."
  @type status_info :: %{
          status: :pending | :up | :down,
          last_check_at: integer() | nil,
          consecutive_failures: non_neg_integer()
        }

  @doc """
  Starts and links a monitor process.

  Options:

    * `:clock` — zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:notify` — two-arity function `notify.(service_name, reason)` invoked when a
      service transitions to `:down`. Defaults to a no-op.

  Any other options (such as `:name`) are passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {clock, opts} = Keyword.pop(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    {notify, opts} = Keyword.pop(opts, :notify, fn _name, _reason -> :ok end)
    GenServer.start_link(__MODULE__, {clock, notify}, opts)
  end

  @doc """
  Registers `service_name` with the given zero-arity `check_func`.

  Checks begin `interval_ms` milliseconds after registration and repeat on that
  interval. The service starts in status `:pending` with no failures and no
  `last_check_at`. After `max_failures` consecutive failures the service is marked
  `:down` and the monitor's `:notify` function is invoked once.

  Returns `:ok`, or `{:error, :already_registered}` if the name is already taken; an
  existing registration is never replaced or altered.
  """
  @spec register(GenServer.server(), term(), (-> :ok | {:error, term()}), pos_integer(),
          pos_integer()) :: :ok | {:error, :already_registered}
  def register(server, service_name, check_func, interval_ms, max_failures \\ @default_max_failures)
      when is_function(check_func, 0) and is_integer(interval_ms) and interval_ms > 0 and
             is_integer(max_failures) and max_failures > 0 do
    GenServer.call(server, {:register, service_name, check_func, interval_ms, max_failures})
  end

  @doc """
  Removes `service_name` from monitoring.

  Always returns `:ok`, whether or not the service was registered. Pending timers for
  the removed registration are neutralised: they will not run the check function, fire
  notifications, or affect a later registration under the same name.
  """
  @spec deregister(GenServer.server(), term()) :: :ok
  def deregister(server, service_name) do
    GenServer.call(server, {:deregister, service_name})
  end

  @doc """
  Returns `{:ok, status_info}` for a registered service, or `{:error, :not_found}`.

  The `status_info` map contains `:status`, `:last_check_at` and
  `:consecutive_failures`.
  """
  @spec status(GenServer.server(), term()) :: {:ok, status_info()} | {:error, :not_found}
  def status(server, service_name) do
    GenServer.call(server, {:status, service_name})
  end

  @doc """
  Returns a map of every registered service name to its `status_info` map.
  """
  @spec statuses(GenServer.server()) :: %{optional(term()) => status_info()}
  def statuses(server) do
    GenServer.call(server, :statuses)
  end

  @impl true
  @spec init({(-> integer()), (term(), term() -> any())}) :: {:ok, %__MODULE__{}}
  def init({clock, notify}) do
    {:ok, %__MODULE__{clock: clock, notify: notify}}
  end

  @impl true
  def handle_call({:register, name, check_func, interval_ms, max_failures}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, _existing} ->
        {:reply, {:error, :already_registered}, state}

      :error ->
        epoch = state.next_epoch

        service = %{
          check_func: check_func,
          interval_ms: interval_ms,
          max_failures: max_failures,
          status: :pending,
          consecutive_failures: 0,
          last_check_at: nil,
          notified: false,
          epoch: epoch
        }

        Process.send_after(self(), {:check, name}, interval_ms)

        state = %{
          state
          | services: Map.put(state.services, name, service),
            next_epoch: epoch + 1
        }

        {:reply, :ok, state}
    end
  end

  def handle_call({:deregister, name}, _from, state) do
    {:reply, :ok, %{state | services: Map.delete(state.services, name)}}
  end

  def handle_call({:status, name}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, service} -> {:reply, {:ok, public_view(service)}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:statuses, _from, state) do
    views = Map.new(state.services, fn {name, service} -> {name, public_view(service)} end)
    {:reply, views, state}
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end

  @impl true
  def handle_cast(_msg, state), do: {:noreply, state}

  @impl true
  def handle_info({:check, name}, state) do
    case Map.fetch(state.services, name) do
      {:ok, service} -> {:noreply, run_check(state, name, service)}
      :error -> {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Runs one check for `name`, updates its bookkeeping, fires `notify` if the service
  # just crossed its failure threshold, and schedules the next check.
  #
  # The service is re-fetched after the check function runs so that a `deregister`
  # (or a re-`register`) performed from within the check function cannot be undone,
  # and so a stale timer for a replaced registration never drives the new one.
  defp run_check(state, name, service) do
    epoch = service.epoch
    result = safe_check(service.check_func)
    now = state.clock.()

    case Map.fetch(state.services, name) do
      {:ok, %{epoch: ^epoch} = current} ->
        {updated, notification} = apply_result(current, result, now)
        emit(state.notify, name, notification)
        Process.send_after(self(), {:check, name}, updated.interval_ms)
        %{state | services: Map.put(state.services, name, updated)}

      _other ->
        state
    end
  end

  defp safe_check(check_func) do
    case check_func.() do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp apply_result(service, :ok, now) do
    updated = %{
      service
      | status: :up,
        consecutive_failures: 0,
        last_check_at: now,
        notified: false
    }

    {updated, :none}
  end

  defp apply_result(service, {:error, reason}, now) do
    failures = service.consecutive_failures + 1

    updated = %{service | consecutive_failures: failures, last_check_at: now}

    cond do
      failures < service.max_failures ->
        {updated, :none}

      updated.notified ->
        {%{updated | status: :down}, :none}

      true ->
        {%{updated | status: :down, notified: true}, {:notify, reason}}
    end
  end

  defp emit(_notify, _name, :none), do: :ok

  defp emit(notify, name, {:notify, reason}) do
    notify.(name, reason)
    :ok
  end

  defp public_view(service) do
    %{
      status: service.status,
      last_check_at: service.last_check_at,
      consecutive_failures: service.consecutive_failures
    }
  end
end