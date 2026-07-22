defmodule RateMonitor do
  @moduledoc """
  A `GenServer` that supervises registered services by periodically running each
  service's health-check function and judging health by the **failure rate over a
  rolling window** of the most recent checks.

  Each service runs on its own `interval_ms` timer. A completed check appends its
  outcome to a bounded window (`window_size` entries). The failure rate is
  `number_of_errors / length(window)`. Once the window is full, the service is
  `:down` when the failure rate is greater than or equal to the configured
  `threshold`, and `:up` otherwise. While the window is only partially filled the
  service can never be `:down`.

  Recovery is rate-driven: a `:down` service returns to `:up` only once enough new
  outcomes pull the full window's failure rate back below the threshold.

  The module relies solely on the OTP standard library.
  """

  use GenServer

  @typedoc "A service health-check: returns `:ok` or `{:error, reason}`."
  @type check_func :: (-> :ok | {:error, term()})

  @typedoc "Public, read-only status snapshot for a single service."
  @type status_info :: %{
          status: :pending | :up | :down,
          last_check_at: integer() | nil,
          failure_rate: float(),
          checks_in_window: non_neg_integer()
        }

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Starts and links a `RateMonitor` process.

  Options:

    * `:clock` — zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:notify` — two-arity function `notify.(service_name, failure_rate)` invoked
      once when a service transitions to `:down`. Defaults to a no-op.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Registers `service_name` with the given `check_func` and `interval_ms`.

  Options:

    * `:window_size` — number of recent checks the rolling window holds
      (default `5`).
    * `:threshold` — failure rate in `0.0..1.0` at or above which the service is
      marked `:down` (default `0.6`).

  Returns `:ok`, or `{:error, :already_registered}` if the name is already
  registered. An existing registration is never replaced by a second call.
  """
  @spec register(
          GenServer.server(),
          term(),
          check_func(),
          non_neg_integer(),
          keyword()
        ) :: :ok | {:error, :already_registered}
  def register(server, service_name, check_func, interval_ms, opts \\ []) do
    GenServer.call(server, {:register, service_name, check_func, interval_ms, opts})
  end

  @doc """
  Removes `service_name` from monitoring. Always returns `:ok`, whether or not the
  service was registered. Any pending or future timer for the removed registration
  has no effect afterwards.
  """
  @spec deregister(GenServer.server(), term()) :: :ok
  def deregister(server, service_name) do
    GenServer.call(server, {:deregister, service_name})
  end

  @doc """
  Returns `{:ok, status_info}` for a registered service, or `{:error, :not_found}`
  otherwise.
  """
  @spec status(GenServer.server(), term()) ::
          {:ok, status_info()} | {:error, :not_found}
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

  # ── GenServer callbacks ─────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    notify = Keyword.get(opts, :notify, fn _name, _rate -> :ok end)
    {:ok, %{clock: clock, notify: notify, services: %{}}}
  end

  @impl true
  def handle_call({:register, name, check_func, interval_ms, opts}, _from, state) do
    if Map.has_key?(state.services, name) do
      {:reply, {:error, :already_registered}, state}
    else
      service = new_service(name, check_func, interval_ms, opts)
      {:reply, :ok, put_in(state.services[name], service)}
    end
  end

  def handle_call({:deregister, name}, _from, state) do
    case Map.get(state.services, name) do
      nil ->
        {:reply, :ok, state}

      service ->
        cancel_and_flush(service.timer_ref, name)
        {:reply, :ok, %{state | services: Map.delete(state.services, name)}}
    end
  end

  def handle_call({:status, name}, _from, state) do
    case Map.get(state.services, name) do
      nil -> {:reply, {:error, :not_found}, state}
      service -> {:reply, {:ok, status_info(service)}, state}
    end
  end

  def handle_call(:statuses, _from, state) do
    result = Map.new(state.services, fn {name, s} -> {name, status_info(s)} end)
    {:reply, result, state}
  end

  @impl true
  def handle_info({:check, name}, state) do
    case Map.get(state.services, name) do
      nil ->
        {:noreply, state}

      service ->
        updated = run_check(service, name, state)
        {:noreply, put_in(state.services[name], updated)}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Internal helpers ────────────────────────────────────────────────────────

  @spec new_service(term(), check_func(), non_neg_integer(), keyword()) :: map()
  defp new_service(name, check_func, interval_ms, opts) do
    %{
      check_func: check_func,
      interval_ms: interval_ms,
      window_size: Keyword.get(opts, :window_size, 5),
      threshold: Keyword.get(opts, :threshold, 0.6),
      status: :pending,
      history: [],
      last_check_at: nil,
      failure_rate: +0.0,
      checks_in_window: 0,
      timer_ref: schedule(name, interval_ms)
    }
  end

  @spec run_check(map(), term(), map()) :: map()
  defp run_check(service, name, state) do
    outcome = classify(service.check_func)
    history = Enum.take(service.history ++ [outcome], -service.window_size)
    checks = length(history)
    errors = Enum.count(history, &(&1 == :error))
    failure_rate = if checks == 0, do: +0.0, else: errors / checks
    full? = checks == service.window_size

    new_status =
      next_status(full?, failure_rate, service.threshold, service.status, outcome, errors)

    maybe_notify(state.notify, name, service.status, new_status, failure_rate)

    cancel_timer(service.timer_ref)

    %{
      service
      | history: history,
        checks_in_window: checks,
        failure_rate: failure_rate,
        last_check_at: state.clock.(),
        status: new_status,
        timer_ref: schedule(name, service.interval_ms)
    }
  end

  @spec classify(check_func()) :: :ok | :error
  defp classify(check_func) do
    case check_func.() do
      :ok -> :ok
      _other -> :error
    end
  end

  @spec next_status(boolean(), float(), float(), atom(), :ok | :error, non_neg_integer()) ::
          :pending | :up | :down
  defp next_status(true, failure_rate, threshold, _old, _outcome, _errors) do
    if failure_rate >= threshold, do: :down, else: :up
  end

  defp next_status(false, _rate, _threshold, old, outcome, errors) do
    cond do
      errors == 0 -> :up
      old == :up -> :up
      outcome == :ok -> :up
      true -> :pending
    end
  end

  @spec maybe_notify((term(), float() -> any()), term(), atom(), atom(), float()) :: :ok
  defp maybe_notify(notify, name, old, new, failure_rate) do
    if new == :down and old != :down do
      notify.(name, failure_rate)
    end

    :ok
  end

  @spec status_info(map()) :: status_info()
  defp status_info(service) do
    %{
      status: service.status,
      last_check_at: service.last_check_at,
      failure_rate: service.failure_rate,
      checks_in_window: service.checks_in_window
    }
  end

  @spec schedule(term(), non_neg_integer()) :: reference()
  defp schedule(name, interval_ms) do
    Process.send_after(self(), {:check, name}, interval_ms)
  end

  @spec cancel_timer(reference() | nil) :: any()
  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  @spec cancel_and_flush(reference() | nil, term()) :: :ok
  defp cancel_and_flush(nil, _name), do: :ok

  defp cancel_and_flush(ref, name) do
    case Process.cancel_timer(ref) do
      false ->
        receive do
          {:check, ^name} -> :ok
        after
          0 -> :ok
        end

      _left ->
        :ok
    end

    :ok
  end
end