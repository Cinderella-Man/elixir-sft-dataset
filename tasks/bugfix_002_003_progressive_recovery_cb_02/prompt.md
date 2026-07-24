# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

Hey — I need you to write me an Elixir GenServer module called `ProgressiveRecoveryCircuitBreaker`. It's a **four-state** circuit breaker, and the whole point is that recovery is gradual rather than instantaneous.

Here's why I want it: in a standard three-state breaker, a single successful probe in half-open state flips the circuit straight back to fully closed. If the underlying service is flaky but not fully healed, that causes rapid re-tripping — flapping. So this variant adds a new state, `:recovering`, sitting between half-open and closed. After a successful probe, instead of snapping shut, the circuit enters a multi-stage recovery process with increasing call volumes and increasing (but still strict) failure tolerance at each stage. Only after clearing the final stage does the circuit return to fully closed.

The states I want are: `:closed` (normal), `:open` (fail fast), `:half_open` (single probe), and `:recovering` (progressive rebuild of trust).

For the API, start with `ProgressiveRecoveryCircuitBreaker.start_link(opts)`, and it should take these options:

- `:name` — required process registration name.
- `:failure_threshold` — consecutive failures in closed state before tripping (default 5).
- `:reset_timeout_ms` — time to stay open before moving to half-open (default 30_000).
- `:half_open_max_probes` — probes allowed in half-open (default 1).
- `:recovery_stages` — a list of `{calls_required, failures_tolerated}` tuples defining the recovery ladder. After a successful half-open probe, the circuit enters the first stage. Each stage requires the specified number of calls to complete, tolerating at most the specified number of failures during that stage. Clearing the last stage transitions to `:closed`. Exceeding tolerance at any stage transitions back to `:open`. Default: `[{5, 0}, {15, 1}, {30, 2}]` — so first prove 5 calls with zero failures, then 15 calls with at most 1 failure, then 30 calls with at most 2 failures.
- `:clock` — zero-arity function returning current time in milliseconds (default `fn -> System.monotonic_time(:millisecond) end`).

Then `ProgressiveRecoveryCircuitBreaker.call(name, func)`, where `func` is a zero-arity function. Here's how each state should behave:

- **Closed**: execute `func`; on success reset the consecutive failure count; on failure increment it and trip to `:open` if it reaches `failure_threshold` (i.e. the count `>=` the threshold). Return whatever `func` returned (or `{:error, exception}` if it raised).
- **Open**: return `{:error, :circuit_open}` immediately without executing `func`. Transition to `:half_open` once at least `reset_timeout_ms` has elapsed since the circuit opened (elapsed `>=` `reset_timeout_ms`). This elapsed check is measured against `:clock` and is evaluated on demand, so a bare `state(name)` query — with no intervening `call` — will report `:half_open` once enough time has passed.
- **Half-open**: allow up to `half_open_max_probes` calls through as probes. A call that exceeds the probe budget (including the case where `half_open_max_probes` is 0) returns `{:error, :circuit_open}` without executing `func` and leaves the circuit in `:half_open`. Probe success → `:recovering` (starting at stage 0). Probe failure → `:open` with a restarted reset timer (the elapsed clock is measured from this new open transition). A probe returns whatever `func` returned.
- **Recovering**: every call executes normally, returning whatever `func` returned (or `{:error, exception}` if it raised), exactly as in the closed state. Track calls completed and failures within the current stage. If `stage_failures > failures_tolerated`, transition to `:open` with the reset timer restarted (checked before the advance condition). When `stage_calls >= calls_required`, advance to the next stage (with fresh counters) — or transition to `:closed` if already at the final stage.

I also want `ProgressiveRecoveryCircuitBreaker.state(name)` returning `:closed | :open | :half_open | :recovering`, and `ProgressiveRecoveryCircuitBreaker.reset(name)` which manually resets to `:closed` with all counters zeroed (failure count, stage counters, recovery stage index).

Outcome classification should be the same as a standard breaker: `{:ok, value}` is a success; `{:error, reason}` or a raised exception is a failure. On raise, catch and return `{:error, exception_struct}` without crashing the GenServer (e.g. a raised `RuntimeError` yields `{:error, %RuntimeError{message: "boom"}}`). Any other return shape is also a failure.

Keep it to a single file, no external dependencies.

## The buggy module

```elixir
defmodule ProgressiveRecoveryCircuitBreaker do
  @moduledoc """
  A four-state circuit breaker that replaces the standard instant-recovery
  behavior (a single successful probe flips back to closed) with a multi-stage
  trust rebuild.

  ## State machine

      :closed ──(failure_threshold consecutive failures)──▶ :open
      :open ──(reset_timeout_ms elapsed)──▶ :half_open
      :half_open ──(probe success)──▶ :recovering (stage 0)
      :half_open ──(probe failure)──▶ :open
      :recovering ──(stage cleared, not last)──▶ :recovering (next stage)
      :recovering ──(last stage cleared)──▶ :closed
      :recovering ──(stage_failures > tolerated)──▶ :open

  Each recovery stage is a `{calls_required, failures_tolerated}` pair.  The
  circuit must complete `calls_required` calls at the stage with no more than
  `failures_tolerated` failures to advance.  The default ladder
  `[{5, 0}, {15, 1}, {30, 2}]` requires progressively more evidence of
  stability while tolerating progressively more failures per stage.

  Every call in `:recovering` executes normally — this variant does not
  sample or reject traffic during recovery, it just uses the additional
  observations to decide when to declare full health.

  ## Options

    * `:name`                  – required registered name
    * `:failure_threshold`     – default 5
    * `:reset_timeout_ms`      – default 30_000
    * `:half_open_max_probes`  – default 1
    * `:recovery_stages`       – default `[{5, 0}, {15, 1}, {30, 2}]`
    * `:clock`                 – `(-> integer())` current time in ms

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Runs `func`; returns its result or `{:error, :circuit_open}` (progressive recovery)."
  @spec call(GenServer.server(), (-> any())) :: any()
  def call(name, func) when is_function(func, 1) do
    GenServer.call(name, {:call, func})
  end

  @spec state(GenServer.server()) :: :closed | :open | :half_open | :recovering
  def state(name), do: GenServer.call(name, :get_state)

  @spec reset(GenServer.server()) :: :ok
  def reset(name), do: GenServer.call(name, :reset)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @default_recovery_stages [{5, 0}, {15, 1}, {30, 2}]

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    stages = Keyword.get(opts, :recovery_stages, @default_recovery_stages)

    if stages == [] do
      raise ArgumentError, ":recovery_stages must be a non-empty list"
    end

    config = %{
      failure_threshold: Keyword.get(opts, :failure_threshold, 5),
      reset_timeout_ms: Keyword.get(opts, :reset_timeout_ms, 30_000),
      half_open_max_probes: Keyword.get(opts, :half_open_max_probes, 1),
      recovery_stages: stages
    }

    {:ok,
     %{
       state: :closed,
       failure_count: 0,
       opened_at: nil,
       probes_in_flight: 0,
       recovery_stage: 0,
       stage_calls: 0,
       stage_failures: 0,
       clock: clock,
       config: config
     }}
  end

  @impl true
  def handle_call({:call, func}, _from, state) do
    state = maybe_expire_open(state)

    case state.state do
      :closed ->
        {reply, new_state} = execute_in_closed(state, func)
        {:reply, reply, new_state}

      :open ->
        {:reply, {:error, :circuit_open}, state}

      :half_open ->
        if state.probes_in_flight < state.config.half_open_max_probes do
          state = %{state | probes_in_flight: state.probes_in_flight + 1}
          {reply, new_state} = execute_in_half_open(state, func)
          {:reply, reply, new_state}
        else
          {:reply, {:error, :circuit_open}, state}
        end

      :recovering ->
        {reply, new_state} = execute_in_recovering(state, func)
        {:reply, reply, new_state}
    end
  end

  def handle_call(:get_state, _from, state) do
    state = maybe_expire_open(state)
    {:reply, state.state, state}
  end

  def handle_call(:reset, _from, state) do
    {:reply, :ok, reset_state(state)}
  end

  # ---------------------------------------------------------------------------
  # Per-state execution
  # ---------------------------------------------------------------------------

  defp execute_in_closed(state, func) do
    case execute_and_classify(func) do
      {:ok, reply} ->
        # Consecutive failure run is broken — reset counter.
        {reply, %{state | failure_count: 0}}

      {:error, reply} ->
        new_count = state.failure_count + 1

        if new_count >= state.config.failure_threshold do
          {reply, %{state | state: :open, opened_at: state.clock.(), failure_count: 0}}
        else
          {reply, %{state | failure_count: new_count}}
        end
    end
  end

  defp execute_in_half_open(state, func) do
    case execute_and_classify(func) do
      {:ok, reply} ->
        # Probe cleared — begin staged recovery from stage 0.
        {reply,
         %{
           state
           | state: :recovering,
             recovery_stage: 0,
             stage_calls: 0,
             stage_failures: 0,
             probes_in_flight: 0,
             opened_at: nil,
             failure_count: 0
         }}

      {:error, reply} ->
        {reply, %{state | state: :open, opened_at: state.clock.(), probes_in_flight: 0}}
    end
  end

  defp execute_in_recovering(state, func) do
    {outcome, reply} = execute_and_classify(func)

    # 1. Calculate updated counters based on the latest call
    new_stage_calls = state.stage_calls + 1

    new_stage_failures =
      case outcome do
        :error -> state.stage_failures + 1
        :ok -> state.stage_failures
      end

    # 2. Extract limits once using pattern matching
    {required_calls, tolerated_failures} =
      Enum.at(state.config.recovery_stages, state.recovery_stage)

    # 3. Create a temporary state that reflects the current progress
    # This ensures any delegation (like advance_stage) has the "truth"
    updated_state = %{state | stage_calls: new_stage_calls, stage_failures: new_stage_failures}

    cond do
      # Scenario A: Failure limit exceeded -> Crash back to :open
      new_stage_failures > tolerated_failures ->
        new_state = %{
          updated_state
          | # Start with updated counts, then override for :open
            state: :open,
            opened_at: state.clock.(),
            recovery_stage: 0,
            stage_calls: 0,
            stage_failures: 0
        }

        {reply, new_state}

      # Scenario B: Target reached -> Try to move to next stage or close
      new_stage_calls >= required_calls ->
        advance_stage(updated_state, reply)

      # Scenario C: Progressing -> Stay in :recovering with new counts
      true ->
        {reply, updated_state}
    end
  end

  defp advance_stage(state, reply) do
    next_stage = state.recovery_stage + 1

    if next_stage >= length(state.config.recovery_stages) do
      # Final stage cleared → full closure.
      {reply,
       %{
         state
         | state: :closed,
           recovery_stage: 0,
           stage_calls: 0,
           stage_failures: 0,
           failure_count: 0
       }}
    else
      # Move to next stage with fresh counters.
      {reply, %{state | recovery_stage: next_stage, stage_calls: 0, stage_failures: 0}}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Returns `{:ok | :error, reply}` where the atom is the outcome for state
  # bookkeeping and `reply` is what the caller sees.
  defp execute_and_classify(func) do
    try do
      case func.() do
        {:ok, _value} = ok -> {:ok, ok}
        {:error, _reason} = err -> {:error, err}
        # Anything that is not {:ok, _} counts as a failure for the state
        # bookkeeping, but the caller still sees exactly what func returned.
        other -> {:error, other}
      end
    rescue
      exception -> {:error, {:error, exception}}
    end
  end

  defp maybe_expire_open(%{state: :open} = state) do
    if state.clock.() - state.opened_at >= state.config.reset_timeout_ms do
      %{state | state: :half_open, probes_in_flight: 0}
    else
      state
    end
  end

  defp maybe_expire_open(state), do: state

  defp reset_state(state) do
    %{
      state
      | state: :closed,
        failure_count: 0,
        opened_at: nil,
        probes_in_flight: 0,
        recovery_stage: 0,
        stage_calls: 0,
        stage_failures: 0
    }
  end
end
```

## Failing test report

```
26 of 26 test(s) failed:

  * test passes through successes in closed state
      no function clause matching in ProgressiveRecoveryCircuitBreaker.call/2

  * test trips on threshold consecutive failures
      no function clause matching in ProgressiveRecoveryCircuitBreaker.call/2

  * test success between failures resets consecutive failure count
      no function clause matching in ProgressiveRecoveryCircuitBreaker.call/2

  * test open state rejects calls without executing
      no function clause matching in ProgressiveRecoveryCircuitBreaker.call/2

  (…22 more)
```
