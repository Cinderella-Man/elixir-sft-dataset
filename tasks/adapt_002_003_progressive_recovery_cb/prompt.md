# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

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

## New specification

Write me an Elixir GenServer module called `ProgressiveRecoveryCircuitBreaker` that implements a **four-state** circuit breaker where recovery is gradual rather than instantaneous.

The motivation: in a standard three-state breaker, a single successful probe in half-open state flips the circuit back to fully closed. If the underlying service is flaky but not fully healed, this causes rapid re-tripping (flapping). This variant adds a new state — `:recovering` — between half-open and closed. After a successful probe, the circuit enters a multi-stage recovery process with increasing call volumes and increasing (but still strict) failure tolerance at each stage. Only after clearing the final stage does the circuit return to fully closed.

States: `:closed` (normal), `:open` (fail fast), `:half_open` (single probe), `:recovering` (progressive rebuild of trust).

API:

- `ProgressiveRecoveryCircuitBreaker.start_link(opts)` with options:
  - `:name` — required process registration name
  - `:failure_threshold` — consecutive failures in closed state before tripping (default 5)
  - `:reset_timeout_ms` — time to stay open before moving to half-open (default 30_000)
  - `:half_open_max_probes` — probes allowed in half-open (default 1)
  - `:recovery_stages` — a list of `{calls_required, failures_tolerated}` tuples defining the recovery ladder. After a successful half-open probe, the circuit enters the first stage. Each stage requires the specified number of calls to complete, tolerating at most the specified number of failures during that stage. Clearing the last stage transitions to `:closed`. Exceeding tolerance at any stage transitions back to `:open`. Default: `[{5, 0}, {15, 1}, {30, 2}]` — first prove 5 calls with zero failures, then 15 calls with at most 1 failure, then 30 calls with at most 2 failures.
  - `:clock` — zero-arity function returning current time in milliseconds (default `fn -> System.monotonic_time(:millisecond) end`)

- `ProgressiveRecoveryCircuitBreaker.call(name, func)` where `func` is a zero-arity function:
  - **Closed**: execute `func`; on success reset the consecutive failure count; on failure increment it and trip to `:open` if it reaches `failure_threshold`. Return whatever `func` returned (or `{:error, exception}` if it raised).
  - **Open**: return `{:error, :circuit_open}` immediately. Transition to `:half_open` once `reset_timeout_ms` has elapsed.
  - **Half-open**: allow up to `half_open_max_probes` calls through. Probe success → `:recovering` (starting at stage 0). Probe failure → `:open` with a restarted reset timer.
  - **Recovering**: every call executes normally. Track calls completed and failures within the current stage. If `stage_failures > failures_tolerated`, transition to `:open` with the reset timer restarted. When `stage_calls >= calls_required`, advance to the next stage (with fresh counters) — or transition to `:closed` if already at the final stage.

- `ProgressiveRecoveryCircuitBreaker.state(name)` returns `:closed | :open | :half_open | :recovering`.

- `ProgressiveRecoveryCircuitBreaker.reset(name)` manually resets to `:closed` with all counters zeroed (failure count, stage counters, recovery stage index).

Outcome classification is the same as a standard breaker: `{:ok, value}` is a success; `{:error, reason}` or a raised exception is a failure. On raise, catch and return `{:error, exception_struct}` without crashing the GenServer. Any other return shape is also a failure.

Single file, no external dependencies.
