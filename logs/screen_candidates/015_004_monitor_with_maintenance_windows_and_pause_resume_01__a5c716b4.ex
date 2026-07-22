defmodule ManagedMonitor do
  @moduledoc """
  A `GenServer` that supervises registered services with periodic health checks
  and layers operational controls on top of plain up/down monitoring.

  Each registered service is checked on its own timer. Beyond reporting a health
  of `:pending`, `:up`, or `:down`, a service can be:

    * **paused** — its check timer keeps firing but the check function is not run
      and nothing about the service changes;
    * **in a maintenance window** — checks still run (and `:last_check_at` is
      updated) but failures are forgiven and can never drive a `:down`
      transition; the window expires automatically after a fixed duration.

  Services are fully independent: one service's failures, pauses, or maintenance
  windows never affect another's health, counters, or windows.

  Only the OTP standard library is used.
  """

  use GenServer

  @typedoc "A zero-arity health check returning `:ok` or `{:error, reason}`."
  @type check_func :: (-> :ok | {:error, term()})

  @typedoc "A status map describing a single service."
  @type status_info :: %{
          status: :pending | :up | :down | :paused | :maintenance,
          health: :pending | :up | :down,
          last_check_at: integer() | nil,
          consecutive_failures: non_neg_integer(),
          maintenance_ends_at: integer() | nil
        }

  # ── Public API ─────────────────────────────────────────────────────────────

  @spec start_link(keyword()) :: GenServer.on_start()
  @doc """
  Starts and links a monitor process.

  Options:

    * `:clock` — zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:notify` — three-arity function `notify.(name, event, detail)` invoked on
      lifecycle events. Defaults to a no-op.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec register(GenServer.server(), term(), check_func(), pos_integer(), pos_integer()) ::
          :ok | {:error, :already_registered}
  @doc """
  Registers `service_name` with a `check_func`, a check `interval_ms`, and a
  `max_failures` threshold (default `3`).

  Returns `:ok`, or `{:error, :already_registered}` if the name is taken. The
  service starts `:pending` with a `0` failure counter and a `nil`
  `last_check_at`; the first check is scheduled `interval_ms` later.
  """
  def register(server, service_name, check_func, interval_ms, max_failures \\ 3) do
    GenServer.call(server, {:register, service_name, check_func, interval_ms, max_failures})
  end

  @spec pause(GenServer.server(), term()) :: :ok | {:error, :not_found}
  @doc """
  Pauses monitoring for `service_name`. Timers keep firing but the check
  function is not executed. Returns `:ok`, or `{:error, :not_found}`.
  """
  def pause(server, service_name) do
    GenServer.call(server, {:pause, service_name})
  end

  @spec resume(GenServer.server(), term()) ::
          :ok | {:error, :not_paused | :not_found}
  @doc """
  Resumes a service that is currently paused or in maintenance, reverting its
  status to the preserved health and retiring any pending maintenance expiry.

  Returns `:ok`; `{:error, :not_paused}` if the service is neither paused nor in
  maintenance; `{:error, :not_found}` for an unknown service.
  """
  def resume(server, service_name) do
    GenServer.call(server, {:resume, service_name})
  end

  @spec maintenance(GenServer.server(), term(), non_neg_integer()) ::
          :ok | {:error, :not_found}
  @doc """
  Puts `service_name` into maintenance mode for `duration_ms` milliseconds,
  replacing any existing window. Returns `:ok`, or `{:error, :not_found}`.
  """
  def maintenance(server, service_name, duration_ms) do
    GenServer.call(server, {:maintenance, service_name, duration_ms})
  end

  @spec deregister(GenServer.server(), term()) :: :ok
  @doc """
  Removes `service_name` from monitoring and retires all of its scheduled
  messages. Always returns `:ok`, whether or not the service existed.
  """
  def deregister(server, service_name) do
    GenServer.call(server, {:deregister, service_name})
  end

  @spec status(GenServer.server(), term()) ::
          {:ok, status_info()} | {:error, :not_found}
  @doc """
  Returns `{:ok, status_info}` for a registered service, or
  `{:error, :not_found}`.
  """
  def status(server, service_name) do
    GenServer.call(server, {:status, service_name})
  end

  @spec statuses(GenServer.server()) :: %{optional(term()) => status_info()}
  @doc "Returns a map of every registered service name to its status map."
  def statuses(server) do
    GenServer.call(server, :statuses)
  end

  # ── GenServer callbacks ──────────────────────────────────────────────────

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    notify = Keyword.get(opts, :notify, fn _name, _event, _detail -> :ok end)
    {:ok, %{clock: clock, notify: notify, services: %{}}}
  end

  @impl true
  def handle_call({:register, name, check_func, interval_ms, max_failures}, _from, state) do
    case fetch(state, name) do
      {:ok, _service} ->
        {:reply, {:error, :already_registered}, state}

      :error ->
        ref = Process.send_after(self(), {:check, name}, interval_ms)

        service = %{
          name: name,
          check_func: check_func,
          interval_ms: interval_ms,
          max_failures: max_failures,
          health: :pending,
          consecutive_failures: 0,
          last_check_at: nil,
          mode: :active,
          maintenance_ends_at: nil,
          maintenance_ref: nil,
          check_ref: ref
        }

        {:reply, :ok, put_service(state, name, service)}
    end
  end

  def handle_call({:pause, name}, _from, state) do
    case fetch(state, name) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, service} ->
        service = service |> retire_maintenance() |> Map.put(:mode, :paused)
        {:reply, :ok, put_service(state, name, service)}
    end
  end

  def handle_call({:resume, name}, _from, state) do
    case fetch(state, name) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, %{mode: mode} = service} when mode in [:paused, :maintenance] ->
        service = service |> retire_maintenance() |> Map.put(:mode, :active)
        {:reply, :ok, put_service(state, name, service)}

      {:ok, _service} ->
        {:reply, {:error, :not_paused}, state}
    end
  end

  def handle_call({:maintenance, name, duration_ms}, _from, state) do
    case fetch(state, name) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, service} ->
        service = retire_maintenance(service)
        now = state.clock.()
        ref = Process.send_after(self(), {:maintenance_end, name}, duration_ms)

        service = %{
          service
          | mode: :maintenance,
            maintenance_ends_at: now + duration_ms,
            maintenance_ref: ref
        }

        notify(state, name, :maintenance_started, duration_ms)
        {:reply, :ok, put_service(state, name, service)}
    end
  end

  def handle_call({:deregister, name}, _from, state) do
    case fetch(state, name) do
      :error ->
        {:reply, :ok, state}

      {:ok, service} ->
        retire_check(service)
        retire_maintenance(service)
        {:reply, :ok, %{state | services: Map.delete(state.services, name)}}
    end
  end

  def handle_call({:status, name}, _from, state) do
    case fetch(state, name) do
      :error -> {:reply, {:error, :not_found}, state}
      {:ok, service} -> {:reply, {:ok, status_info(service)}, state}
    end
  end

  def handle_call(:statuses, _from, state) do
    result = Map.new(state.services, fn {name, service} -> {name, status_info(service)} end)
    {:reply, result, state}
  end

  @impl true
  def handle_info({:check, name}, state) do
    case fetch(state, name) do
      :error ->
        {:noreply, state}

      {:ok, service} ->
        ref = Process.send_after(self(), {:check, name}, service.interval_ms)
        service = run_check(%{service | check_ref: ref}, state)
        {:noreply, put_service(state, name, service)}
    end
  end

  def handle_info({:maintenance_end, name}, state) do
    case fetch(state, name) do
      {:ok, %{mode: :maintenance} = service} ->
        notify(state, name, :maintenance_ended, nil)

        service = %{
          service
          | mode: :active,
            maintenance_ends_at: nil,
            maintenance_ref: nil
        }

        {:noreply, put_service(state, name, service)}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Check logic ────────────────────────────────────────────────────────────

  # Paused: the check function is never invoked and nothing changes.
  defp run_check(%{mode: :paused} = service, _state), do: service

  # Maintenance: run the check, update last_check_at, but forgive failures.
  defp run_check(%{mode: :maintenance} = service, state) do
    now = state.clock.()

    case service.check_func.() do
      :ok ->
        %{service | last_check_at: now, consecutive_failures: 0, health: :up}

      {:error, _reason} ->
        %{service | last_check_at: now}
    end
  end

  # Active: normal monitoring with failure counting and down/recover events.
  defp run_check(%{mode: :active} = service, state) do
    now = state.clock.()

    case service.check_func.() do
      :ok ->
        service = %{service | last_check_at: now, consecutive_failures: 0}
        maybe_recover(service, state)

      {:error, reason} ->
        handle_failure(%{service | last_check_at: now}, state, reason)
    end
  end

  defp maybe_recover(%{health: :down} = service, state) do
    notify(state, service.name, :recovered, nil)
    %{service | health: :up}
  end

  defp maybe_recover(service, _state), do: %{service | health: :up}

  defp handle_failure(service, state, reason) do
    count = service.consecutive_failures + 1
    service = %{service | consecutive_failures: count}

    if service.health != :down and count >= service.max_failures do
      notify(state, service.name, :down, reason)
      %{service | health: :down}
    else
      service
    end
  end

  # ── Status reporting ─────────────────────────────────────────────────────

  defp status_info(service) do
    %{
      status: report_status(service),
      health: service.health,
      last_check_at: service.last_check_at,
      consecutive_failures: service.consecutive_failures,
      maintenance_ends_at: service.maintenance_ends_at
    }
  end

  defp report_status(%{mode: :paused}), do: :paused
  defp report_status(%{mode: :maintenance}), do: :maintenance
  defp report_status(%{health: health}), do: health

  # ── Timer / state helpers ──────────────────────────────────────────────────

  defp retire_maintenance(%{maintenance_ref: nil} = service) do
    %{service | maintenance_ends_at: nil}
  end

  defp retire_maintenance(%{maintenance_ref: ref, name: name} = service) do
    cancel_and_flush(ref, {:maintenance_end, name})
    %{service | maintenance_ref: nil, maintenance_ends_at: nil}
  end

  defp retire_check(%{check_ref: ref, name: name}) do
    cancel_and_flush(ref, {:check, name})
  end

  defp cancel_and_flush(nil, _msg), do: :ok

  defp cancel_and_flush(ref, msg) do
    case Process.cancel_timer(ref) do
      remaining when is_integer(remaining) -> :ok
      false -> flush_message(msg)
    end
  end

  defp flush_message(msg) do
    receive do
      ^msg -> :ok
    after
      0 -> :ok
    end
  end

  defp fetch(state, name), do: Map.fetch(state.services, name)

  defp put_service(state, name, service) do
    %{state | services: Map.put(state.services, name, service)}
  end

  defp notify(state, name, event, detail), do: state.notify.(name, event, detail)
end