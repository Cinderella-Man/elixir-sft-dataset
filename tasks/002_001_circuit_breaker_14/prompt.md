# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `start_link` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `CircuitBreaker` that implements the circuit breaker pattern. It should have three states: closed (normal operation), open (failing fast without calling the function), and half-open (cautiously probing to see if the problem is fixed).

Here's the API I need:

- `CircuitBreaker.start_link(opts)` starts the GenServer. Options are:
  - `:name` — process registration name (required)
  - `:failure_threshold` — how many failures in closed state before tripping to open (default 5)
  - `:reset_timeout_ms` — how long to stay open before moving to half-open (default 30_000)
  - `:half_open_max_probes` — how many calls to allow through in half-open state (default 1)
  - `:clock` — a zero-arity function returning current time in milliseconds, defaults to `fn -> System.monotonic_time(:millisecond) end`

- `CircuitBreaker.call(name, func)` where func is a zero-arity function representing the protected operation. Behavior depends on state:
  - **Closed**: Execute the function. If it returns `{:ok, result}`, return `{:ok, result}`. If it returns `{:error, reason}` or raises, count it as a failure. If failures reach the threshold, transition to open. Return whatever the function returned (or `{:error, reason}` if it raised) — even on the call that trips the breaker, return the function's result, not `{:error, :circuit_open}`.
  - **Open**: Don't execute the function at all. Immediately return `{:error, :circuit_open}`. If at least `reset_timeout_ms` has elapsed since entering the open state (i.e. elapsed time `>= reset_timeout_ms`, so exactly `reset_timeout_ms` counts), transition to half-open instead and let this call through as a probe.
  - **Half-open**: Allow up to `half_open_max_probes` calls through. If a probe succeeds, transition back to closed and reset failure count. If a probe fails, transition back to open and restart the reset timeout (measured from the current clock reading, so the next call fails fast until another full `reset_timeout_ms` elapses). Additional calls beyond the probe limit get `{:error, :circuit_open}`.

- `CircuitBreaker.state(name)` returns the current state as an atom: `:closed`, `:open`, or `:half_open`.

- `CircuitBreaker.reset(name)` manually resets the circuit breaker to closed state with zero failure count, regardless of current state.

A success is when `func` returns `{:ok, value}`. A failure is when `func` returns `{:error, reason}` or raises an exception. A success in closed state resets the failure count to zero, so only consecutive failures accumulate toward the threshold. When the function raises, catch it and return `{:error, %RuntimeError{message: ...}}` or whatever the exception was (returned as the exception struct itself), but don't let it crash the GenServer.

No external dependencies. Single file with the `CircuitBreaker` module.

## The module with `start_link` missing

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

  def start_link(opts) do
    # TODO
  end

  @doc """
  Execute `func` (a zero-arity function) through the circuit breaker.

  Returns `{:ok, result}` on success or `{:error, reason}` on failure /
  when the circuit is open.
  """
  @spec call(name(), (-> any())) :: {:ok, any()} | {:error, any()}
  def call(name, func) when is_function(func, 0) do
    GenServer.call(name, {:call, func})
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

Give me only the complete implementation of `start_link` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
