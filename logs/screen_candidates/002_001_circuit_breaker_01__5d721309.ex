defmodule CircuitBreaker do
  @moduledoc """
  A `GenServer` implementation of the circuit breaker pattern.

  A circuit breaker protects a caller from repeatedly invoking an operation that is
  currently failing. It moves between three states:

    * `:closed` — normal operation. The protected function is executed on every call.
      Consecutive-ish failures are counted, and once the count reaches
      `:failure_threshold` the breaker trips to `:open`.

    * `:open` — failing fast. The protected function is *not* executed and callers get
      `{:error, :circuit_open}` immediately. After `:reset_timeout_ms` has elapsed since
      the breaker entered the open state, the next call transitions the breaker to
      `:half_open` and is let through as a probe.

    * `:half_open` — cautiously probing. Up to `:half_open_max_probes` calls are allowed
      through. A successful probe closes the breaker and resets the failure count; a
      failing probe re-opens it and restarts the reset timeout. Calls beyond the probe
      budget get `{:error, :circuit_open}`.

  ## Success and failure

  The protected function is a zero-arity function. It is considered a *success* when it
  returns `{:ok, value}`. It is considered a *failure* when it returns `{:error, reason}`
  or raises. A raised exception never crashes the breaker: it is caught and returned as
  `{:error, exception_struct}`.

  ## Example

      iex> {:ok, _pid} = CircuitBreaker.start_link(name: :payments, failure_threshold: 2)
      iex> CircuitBreaker.call(:payments, fn -> {:ok, :charged} end)
      {:ok, :charged}
      iex> CircuitBreaker.call(:payments, fn -> {:error, :timeout} end)
      {:error, :timeout}
      iex> CircuitBreaker.call(:payments, fn -> raise "boom" end)
      {:error, %RuntimeError{message: "boom"}}
      iex> CircuitBreaker.state(:payments)
      :open
      iex> CircuitBreaker.call(:payments, fn -> {:ok, :charged} end)
      {:error, :circuit_open}
      iex> CircuitBreaker.reset(:payments)
      :ok
      iex> CircuitBreaker.state(:payments)
      :closed

  The protected function is executed inside the breaker process, so a slow operation
  blocks other callers of the same breaker.
  """

  use GenServer

  @default_failure_threshold 5
  @default_reset_timeout_ms 30_000
  @default_half_open_max_probes 1

  @typedoc "The breaker's current state."
  @type state_name :: :closed | :open | :half_open

  @typedoc "A zero-arity function returning the current time in milliseconds."
  @type clock :: (-> integer())

  @typedoc "A zero-arity protected operation."
  @type operation :: (-> {:ok, term()} | {:error, term()} | term())

  @typedoc "Options accepted by `start_link/1`."
  @type option ::
          {:name, GenServer.name()}
          | {:failure_threshold, pos_integer()}
          | {:reset_timeout_ms, non_neg_integer()}
          | {:half_open_max_probes, pos_integer()}
          | {:clock, clock()}

  defmodule State do
    @moduledoc false

    @enforce_keys [:failure_threshold, :reset_timeout_ms, :half_open_max_probes, :clock]
    defstruct [
      :failure_threshold,
      :reset_timeout_ms,
      :half_open_max_probes,
      :clock,
      :opened_at,
      state: :closed,
      failure_count: 0,
      probes_in_flight: 0
    ]
  end

  @doc """
  Starts the circuit breaker process and links it to the caller.

  ## Options

    * `:name` (required) — the name the process is registered under. Also the name passed
      to `call/2`, `state/1` and `reset/1`.
    * `:failure_threshold` — number of failures in the `:closed` state before the breaker
      trips to `:open`. Defaults to `#{@default_failure_threshold}`.
    * `:reset_timeout_ms` — how long the breaker stays `:open` before a call is allowed
      through as a probe. Defaults to `#{@default_reset_timeout_ms}`.
    * `:half_open_max_probes` — how many calls are let through while `:half_open`.
      Defaults to `#{@default_half_open_max_probes}`.
    * `:clock` — zero-arity function returning the current time in milliseconds. Defaults
      to `fn -> System.monotonic_time(:millisecond) end`. Useful for tests.
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Invokes `func` through the circuit breaker identified by `name`.

  Returns whatever `func` returned (`{:ok, result}` or `{:error, reason}`), or
  `{:error, exception}` if it raised. When the circuit is open — or the half-open probe
  budget is exhausted — `func` is not executed and `{:error, :circuit_open}` is returned.

  The optional `timeout` bounds the `GenServer.call/3` and must therefore accommodate the
  runtime of `func` itself.
  """
  @spec call(GenServer.server(), operation(), timeout()) ::
          {:ok, term()} | {:error, term()} | {:error, :circuit_open}
  def call(name, func, timeout \\ 5_000) when is_function(func, 0) do
    GenServer.call(name, {:call, func}, timeout)
  end

  @doc """
  Returns the current state of the breaker: `:closed`, `:open` or `:half_open`.

  Note that an open breaker whose reset timeout has already elapsed still reports `:open`;
  it only moves to `:half_open` when a call actually arrives to probe with.
  """
  @spec state(GenServer.server()) :: state_name()
  def state(name) do
    GenServer.call(name, :state)
  end

  @doc """
  Manually resets the breaker to `:closed` with a zero failure count.

  Works from any state and always returns `:ok`.
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(name) do
    GenServer.call(name, :reset)
  end

  @impl GenServer
  @spec init([option()]) :: {:ok, State.t()} when State: struct()
  def init(opts) do
    state = %State{
      failure_threshold: Keyword.get(opts, :failure_threshold, @default_failure_threshold),
      reset_timeout_ms: Keyword.get(opts, :reset_timeout_ms, @default_reset_timeout_ms),
      half_open_max_probes:
        Keyword.get(opts, :half_open_max_probes, @default_half_open_max_probes),
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:call, func}, _from, state) do
    state
    |> maybe_expire_open()
    |> dispatch(func)
  end

  def handle_call(:state, _from, state) do
    {:reply, state.state, state}
  end

  def handle_call(:reset, _from, state) do
    {:reply, :ok, close(state)}
  end

  # Executes the protected function (or fails fast) according to the current state.
  defp dispatch(%State{state: :open} = state, _func) do
    {:reply, {:error, :circuit_open}, state}
  end

  defp dispatch(%State{state: :half_open} = state, func) do
    if state.probes_in_flight < state.half_open_max_probes do
      state = %{state | probes_in_flight: state.probes_in_flight + 1}
      result = execute(func)
      {:reply, result, record_result(state, result)}
    else
      {:reply, {:error, :circuit_open}, state}
    end
  end

  defp dispatch(%State{state: :closed} = state, func) do
    result = execute(func)
    {:reply, result, record_result(state, result)}
  end

  # Runs the protected function, converting raises into `{:error, exception}`.
  defp execute(func) do
    try do
      func.()
    rescue
      exception -> {:error, exception}
    end
  end

  # Folds the outcome of a call into the breaker state.
  defp record_result(%State{state: :closed} = state, {:ok, _value}) do
    %{state | failure_count: 0}
  end

  defp record_result(%State{state: :closed} = state, _failure) do
    failure_count = state.failure_count + 1

    if failure_count >= state.failure_threshold do
      open(state)
    else
      %{state | failure_count: failure_count}
    end
  end

  defp record_result(%State{state: :half_open} = state, {:ok, _value}) do
    close(state)
  end

  defp record_result(%State{state: :half_open} = state, _failure) do
    open(state)
  end

  # A call is a success only when it returns `{:ok, value}`; everything else is a failure.

  # Moves an open breaker to half-open once the reset timeout has elapsed.
  defp maybe_expire_open(%State{state: :open, opened_at: opened_at} = state)
       when is_integer(opened_at) do
    if now(state) - opened_at >= state.reset_timeout_ms do
      %{state | state: :half_open, probes_in_flight: 0}
    else
      state
    end
  end

  defp maybe_expire_open(state), do: state

  defp open(state) do
    %{
      state
      | state: :open,
        opened_at: now(state),
        probes_in_flight: 0,
        failure_count: state.failure_threshold
    }
  end

  defp close(state) do
    %{state | state: :closed, opened_at: nil, failure_count: 0, probes_in_flight: 0}
  end

  defp now(%State{clock: clock}), do: clock.()
end