defmodule Monitor do
  @moduledoc """
  A `GenServer` that supervises registered services by running each service's
  health-check function on its own periodic interval and tracking a per-service
  status.

  Each registered service is checked every `interval_ms` milliseconds. A service
  starts in status `:pending`, becomes `:up` on a successful check, and becomes
  `:down` once it accumulates `max_failures` consecutive failing checks. The
  optional `:notify` callback is invoked exactly once each time a service
  transitions into the `:down` state.

  This module relies only on the OTP standard library.
  """

  use GenServer

  @type status :: :pending | :up | :down
  @type check_func :: (-> :ok | {:error, term()})
  @type status_info :: %{
          status: status(),
          last_check_at: integer() | nil,
          consecutive_failures: non_neg_integer()
        }

  # -- Public API ------------------------------------------------------------

  @doc """
  Starts and links the monitor process.

  Supported `opts`:

    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:notify` — a two-arity function `notify.(service_name, reason)` invoked
      when a service transitions to `:down`. Defaults to a no-op.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Registers a service to be monitored.

  Returns `:ok` on success, or `{:error, :already_registered}` when a service
  with `service_name` is already registered. An existing registration is never
  replaced or altered by a second call.

  The service starts in status `:pending`; its first check is scheduled to run
  `interval_ms` milliseconds later.
  """
  @spec register(
          GenServer.server(),
          term(),
          check_func(),
          non_neg_integer(),
          pos_integer()
        ) :: :ok | {:error, :already_registered}
  def register(server, service_name, check_func, interval_ms, max_failures \\ 3) do
    GenServer.call(
      server,
      {:register, service_name, check_func, interval_ms, max_failures}
    )
  end

  @doc """
  Removes a service from monitoring.

  Always returns `:ok`, whether or not `service_name` was registered. Any
  pending or future timer for the removed registration has no effect.
  """
  @spec deregister(GenServer.server(), term()) :: :ok
  def deregister(server, service_name) do
    GenServer.call(server, {:deregister, service_name})
  end

  @doc """
  Returns `{:ok, status_info}` for a registered service, or `{:error,
  :not_found}` otherwise.

  `status_info` contains at least `:status`, `:last_check_at`, and
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

  # -- GenServer callbacks ---------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    notify = Keyword.get(opts, :notify, fn _name, _reason -> :ok end)
    {:ok, %{clock: clock, notify: notify, services: %{}}}
  end

  @impl true
  def handle_call({:register, name, check_func, interval_ms, max_failures}, _from, state) do
    if Map.has_key?(state.services, name) do
      {:reply, {:error, :already_registered}, state}
    else
      ref = make_ref()

      service = %{
        check_func: check_func,
        interval_ms: interval_ms,
        max_failures: max_failures,
        status: :pending,
        consecutive_failures: 0,
        last_check_at: nil,
        ref: ref
      }

      Process.send_after(self(), {:check, name, ref}, interval_ms)
      {:reply, :ok, put_in(state.services[name], service)}
    end
  end

  def handle_call({:deregister, name}, _from, state) do
    {:reply, :ok, %{state | services: Map.delete(state.services, name)}}
  end

  def handle_call({:status, name}, _from, state) do
    case Map.get(state.services, name) do
      nil -> {:reply, {:error, :not_found}, state}
      service -> {:reply, {:ok, status_info(service)}, state}
    end
  end

  def handle_call(:statuses, _from, state) do
    result =
      state.services
      |> Enum.map(fn {name, service} -> {name, status_info(service)} end)
      |> Map.new()

    {:reply, result, state}
  end

  @impl true
  def handle_info({:check, name, ref}, state) do
    case Map.get(state.services, name) do
      %{ref: ^ref} = service ->
        {:noreply, run_check(state, name, service)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # -- Internal helpers ------------------------------------------------------

  @spec run_check(map(), term(), map()) :: map()
  defp run_check(state, name, service) do
    result = service.check_func.()
    now = state.clock.()

    service =
      %{service | last_check_at: now}
      |> apply_result(state, name, result)

    Process.send_after(self(), {:check, name, service.ref}, service.interval_ms)
    put_in(state.services[name], service)
  end

  @spec apply_result(map(), map(), term(), :ok | {:error, term()}) :: map()
  defp apply_result(service, _state, _name, :ok) do
    %{service | consecutive_failures: 0, status: :up}
  end

  defp apply_result(service, state, name, {:error, reason}) do
    failures = service.consecutive_failures + 1

    if failures >= service.max_failures and service.status != :down do
      state.notify.(name, reason)
      %{service | consecutive_failures: failures, status: :down}
    else
      %{service | consecutive_failures: failures}
    end
  end

  @spec status_info(map()) :: status_info()
  defp status_info(service) do
    %{
      status: service.status,
      last_check_at: service.last_check_at,
      consecutive_failures: service.consecutive_failures
    }
  end
end