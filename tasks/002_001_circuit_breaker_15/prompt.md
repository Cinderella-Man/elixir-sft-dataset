# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `call`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

# CircuitBreaker GenServer — circuit breaker pattern

Single-file Elixir module `CircuitBreaker` (a GenServer) implementing the circuit breaker pattern with three states: closed (normal operation), open (fail fast without calling the function), half-open (cautiously probe to see if the problem is fixed). No external dependencies.

**`CircuitBreaker.start_link(opts)`** — starts the GenServer. Options:
- `:name` — process registration name (required)
- `:failure_threshold` — failures in closed state before tripping to open (default 5)
- `:reset_timeout_ms` — time to stay open before moving to half-open (default 30_000)
- `:half_open_max_probes` — calls allowed through in half-open state (default 1)
- `:clock` — zero-arity function returning current time in milliseconds, defaults to `fn -> System.monotonic_time(:millisecond) end`

**`CircuitBreaker.call(name, func)`** — `func` is a zero-arity function representing the protected operation. Behavior by state:
- **Closed**: Execute `func`. If it returns `{:ok, result}`, return `{:ok, result}`. If it returns `{:error, reason}` or raises, count as a failure. If failures reach the threshold, transition to open. Return whatever `func` returned (or `{:error, reason}` if it raised) — even on the call that trips the breaker, return the function's result, not `{:error, :circuit_open}`.
- **Open**: Do not execute `func`. Immediately return `{:error, :circuit_open}`. If at least `reset_timeout_ms` has elapsed since entering the open state (elapsed `>= reset_timeout_ms`, so exactly `reset_timeout_ms` counts), transition to half-open instead and let this call through as a probe.
- **Half-open**: Allow up to `half_open_max_probes` calls through. On probe success, transition back to closed and reset failure count. On probe failure, transition back to open and restart the reset timeout (measured from the current clock reading, so the next call fails fast until another full `reset_timeout_ms` elapses). Calls beyond the probe limit get `{:error, :circuit_open}`.

**`CircuitBreaker.state(name)`** — returns current state atom: `:closed`, `:open`, or `:half_open`.

**`CircuitBreaker.reset(name)`** — manually reset to closed state with zero failure count, regardless of current state.

**Success/failure semantics:**
- Success = `func` returns `{:ok, value}`.
- Failure = `func` returns `{:error, reason}` or raises an exception.
- A success in closed state resets the failure count to zero, so only consecutive failures accumulate toward the threshold.
- When `func` raises, catch it and return `{:error, %RuntimeError{message: ...}}` or whatever the exception was (returned as the exception struct itself); do not let it crash the GenServer.

## The module with `call` missing

```elixir
defmodule CircuitBreaker do
  @moduledoc """
  A GenServer implementing the circuit breaker pattern with three states:

  - **Closed** — normal operation; failures are counted and trip the breaker open
    when they reach the configured threshold. Successes reset the failure count.
  - **Open** — all calls fail fast with `{:error, :circuit_open}` until the
    reset timeout elapses, at which point the breaker moves to half-open.
  - **Half-open** — a limited number of probe calls are allowed through. A
    success resets the breaker to closed; a failure sends it back to open.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @type name :: GenServer.name()

  @doc """
  Starts a `CircuitBreaker` process and links it to the caller.

  ## Options

    * `:name` — process registration name (**required**)
    * `:failure_threshold` — failures before tripping to open (default `5`)
    * `:reset_timeout_ms` — milliseconds in open state before half-open (default `30_000`)
    * `:half_open_max_probes` — concurrent probe calls allowed in half-open (default `1`)
    * `:clock` — zero-arity function returning current time in ms
        (default `fn -> System.monotonic_time(:millisecond) end`)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def call(name, func) when is_function(func, 0) do
    # TODO
  end

  @doc "Returns the current state: `:closed`, `:open`, or `:half_open`."
  @spec state(name()) :: :closed | :open | :half_open
  def state(name) do
    GenServer.call(name, :state)
  end

  @doc "Manually resets the breaker to closed with zero failures."
  @spec reset(name()) :: :ok
  def reset(name) do
    GenServer.call(name, :reset)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    state = %{
      circuit_state: :closed,
      failure_count: 0,
      failure_threshold: Keyword.get(opts, :failure_threshold, 5),
      reset_timeout_ms: Keyword.get(opts, :reset_timeout_ms, 30_000),
      half_open_max_probes: Keyword.get(opts, :half_open_max_probes, 1),
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      opened_at: nil,
      probe_count: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, state.circuit_state, state}
  end

  def handle_call(:reset, _from, state) do
    {:reply, :ok, reset_to_closed(state)}
  end

  def handle_call({:call, func}, _from, state) do
    case state.circuit_state do
      :closed ->
        handle_closed(func, state)

      :open ->
        handle_open(func, state)

      :half_open ->
        handle_half_open(func, state)
    end
  end

  # ---------------------------------------------------------------------------
  # State handlers
  # ---------------------------------------------------------------------------

  defp handle_closed(func, state) do
    {result, success?} = execute(func)

    if success? do
      {:reply, result, %{state | failure_count: 0}}
    else
      new_count = state.failure_count + 1
      new_state = %{state | failure_count: new_count}

      if new_count >= state.failure_threshold do
        {:reply, result, trip_open(new_state)}
      else
        {:reply, result, new_state}
      end
    end
  end

  defp handle_open(func, state) do
    now = state.clock.()
    elapsed = now - state.opened_at

    if elapsed >= state.reset_timeout_ms do
      half_open_state = %{state | circuit_state: :half_open, probe_count: 0}
      handle_half_open(func, half_open_state)
    else
      {:reply, {:error, :circuit_open}, state}
    end
  end

  defp handle_half_open(func, state) do
    if state.probe_count >= state.half_open_max_probes do
      {:reply, {:error, :circuit_open}, state}
    else
      new_state = %{state | probe_count: state.probe_count + 1}
      {result, success?} = execute(func)

      if success? do
        {:reply, result, reset_to_closed(new_state)}
      else
        {:reply, result, trip_open(new_state)}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp execute(func) do
    try do
      case func.() do
        {:ok, _} = ok ->
          {ok, true}

        {:error, _} = error ->
          {error, false}

        other ->
          {{:error, {:unexpected_return, other}}, false}
      end
    rescue
      exception ->
        {{:error, exception}, false}
    end
  end

  defp trip_open(state) do
    %{state | circuit_state: :open, opened_at: state.clock.(), failure_count: 0, probe_count: 0}
  end

  defp reset_to_closed(state) do
    %{state | circuit_state: :closed, failure_count: 0, opened_at: nil, probe_count: 0}
  end
end
```

Output only `call` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
