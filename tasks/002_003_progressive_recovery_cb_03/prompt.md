Implement the private `execute_in_half_open/2` function. It should execute the provided zero-arity function using the `execute_and_classify/1` helper.

If the execution succeeds (`{:ok, reply}`), the probe has cleared. Transition the circuit to the `:recovering` state to begin staged recovery. Initialize the process by setting `recovery_stage`, `stage_calls`, `stage_failures`, `probes_in_flight`, and `failure_count` to 0. Additionally, set `opened_at` to `nil`.

If the execution fails (`{:error, reply}`), the probe has failed. Transition the circuit back to the `:open` state. Record the current time in `opened_at` using the configured `state.clock.()` function and reset `probes_in_flight` to 0.

In both cases, return a tuple containing the `reply` from the execution and the updated state.

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
  stability at progressively higher permitted failure rates.

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

  @spec call(GenServer.server(), (-> any())) :: any()
  def call(name, func) when is_function(func, 0) do
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
          {reply,
           %{state | state: :open, opened_at: state.clock.(), failure_count: 0}}
        else
          {reply, %{state | failure_count: new_count}}
        end
    end
  end

  defp execute_in_half_open(state, func) do
    # TODO
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
          updated_state # Start with updated counts, then override for :open
          | state: :open,
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
      {reply,
       %{state | recovery_stage: next_stage, stage_calls: 0, stage_failures: 0}}
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
        other -> {:error, {:error, {:unexpected_return, other}}}
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