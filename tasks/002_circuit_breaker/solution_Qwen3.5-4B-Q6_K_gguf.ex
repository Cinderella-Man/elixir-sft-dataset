defmodule CircuitBreaker do
  use GenServer

  @doc """
  Starts the circuit breaker GenServer.

  ## Options
    * `:name` - Required. Process registration name.
    * `:failure_threshold` - How many failures in closed state before tripping (default: 5).
    * `:reset_timeout_ms` - How long to stay open before moving to half-open (default: 30_000).
    * `:half_open_max_probes` - How many calls allowed in half-open state (default: 1).
    * `:clock` - Zero-arity function returning current time in ms (default: System.monotonic_time).
  """
  @spec start_link(Keyword.t()) :: {:ok, pid} | {:error, term}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  @doc """
  Calls a function protected by the circuit breaker.

  ## Args
    * `name` - The registered name of the circuit breaker.
    * `func` - A zero-arity function to execute.
  """
  @spec call(atom(), function()) :: {:ok, any()} | {:error, atom()} | {:error, %{message: String.t(), stacktrace: [...]}}
  def call(name, func) do
    GenServer.call(name, {:call, func})
  end

  @doc """
  Returns the current state of the circuit breaker.
  """
  @spec state(atom()) :: :closed | :open | :half_open
  def state(name) do
    GenServer.call(name, {:state, self()})
  end

  @doc """
  Manually resets the circuit breaker to closed state.
  """
  @spec reset(atom()) :: :ok
  def reset(name) do
    GenServer.call(name, {:reset, self()})
  end

  # ---------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------

  def init(opts) do
    default_opts = [
      failure_threshold: 5,
      reset_timeout_ms: 30_000,
      half_open_max_probes: 1,
      clock: fn -> System.monotonic_time(:millisecond) end
    ]

    current_opts = Keyword.merge(default_opts, opts)

    now = current_opts[:clock]().round()

    state = :closed
    failure_count = 0

    start_time = now
    probe_count = 0

    {:ok, %{
      state: state,
      failure_count: failure_count,
      start_time: start_time,
      probe_count: probe_count,
      failure_threshold: current_opts[:failure_threshold],
      reset_timeout_ms: current_opts[:reset_timeout_ms],
      half_open_max_probes: current_opts[:half_open_max_probes],
      clock: current_opts[:clock]
    }}
  end

  # Handle :call request
  def handle_call({:call, func}, from, state) do
    now = state.clock.()
    case do_call(state, now, func) do
      {:ok, result, next_state} ->
        GenServer.reply(from, {:ok, result})
        {:noreply, next_state}

      {:error, reason, next_state} ->
        GenServer.reply(from, {:error, reason})
        {:noreply, next_state}
    end
  end

  # Handle :state request
  def handle_call({:state, _from}, _from, state) do
    GenServer.reply(_from, state.state)
    {:reply, :ok, state}
  end

  # Handle :reset request
  def handle_call({:reset, _from}, _from, state) do
    new_state = %{
      state: :closed,
      failure_count: 0,
      start_time: state.clock.(),
      probe_count: 0,
      failure_threshold: state.failure_threshold,
      reset_timeout_ms: state.reset_timeout_ms,
      half_open_max_probes: state.half_open_max_probes,
      clock: state.clock
    }
    GenServer.reply(_from, :ok)
    {:noreply, new_state}
  end

  # Handle inter-process communication (callbacks from other tasks)
  def handle_cast(msg, state), do: {:noreply, state}
  def handle_info(msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------
  # Private Logic
  # ---------------------------------------------------------------------

  defp do_call(state, now, func) do
    case state.state do
      :closed ->
        if do_execute(state, func) do
          {:ok, :ok, :closed}
        else
          {:error, :circuit_open, :open}
        end

      :open ->
        # Check if enough time has passed to move to half-open
        elapsed = now - state.start_time
        if elapsed >= state.reset_timeout_ms do
          new_probe_count = state.probe_count + 1

          # If we've exceeded probe limit, return error immediately
          if new_probe_count > state.half_open_max_probes do
            {:error, :circuit_open, :open}
          else
            # Allow probe through
            result = do_execute(state, func)
            {:ok, result, handle_probe_result(state, new_probe_count, result)}
          end
        else
          # Still open, return error immediately
          {:error, :circuit_open, :open}
        end

      :half_open ->
        new_probe_count = state.probe_count + 1
        if new_probe_count > state.half_open_max_probes do
          # Too many probes, reject
          {:error, :circuit_open, :open}
        else
          result = do_execute(state, func)
          {:ok, result, handle_probe_result(state, new_probe_count, result)}
        end
    end
  end

  defp do_execute(state, func) do
    try do
      result = func.()
      if result == {:ok, _val} do
        :success
      else
        :failure
      end
    rescue
      e -> :failure
    end
  end

  defp handle_probe_result(state, probe_count, result) do
    # result is {:ok, val} or {:error, reason}
    if elem(result, 0) == :ok do
      # Success: Close circuit, reset failure count
      state
      |> Map.put(:state, :closed)
      |> Map.put(:failure_count, 0)
    else
      # Failure: Stay open (restart timer implicitly by not changing start_time or just keep it)
      # To keep the timer logic simple and consistent with requirements:
      # "If a probe fails, transition back to open and restart the reset timeout."
      # We'll increment failure count and ensure it's >= threshold to force open state logic next call
      state
      |> Map.put(:state, :open)
      |> Map.put(:failure_count, state.failure_count + 1)
    end
  end
end
