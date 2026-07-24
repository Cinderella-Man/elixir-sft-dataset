# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule ProgressiveRecoveryCircuitBreakerTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  setup do
    start_supervised!({Clock, 0})

    # Smaller stage numbers for test tractability
    {:ok, _pid} =
      ProgressiveRecoveryCircuitBreaker.start_link(
        name: :test_cb,
        failure_threshold: 3,
        reset_timeout_ms: 1_000,
        recovery_stages: [{3, 0}, {5, 1}, {10, 2}],
        half_open_max_probes: 1,
        clock: &Clock.now/0
      )

    %{cb: :test_cb}
  end

  defp ok_fn, do: fn -> {:ok, :v} end
  defp err_fn, do: fn -> {:error, :f} end

  # Trips the breaker and advances time so it's in :half_open.
  defp trip_to_half_open(cb) do
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Baseline closed behavior (matches standard CB)
  # -------------------------------------------------------

  test "passes through successes in closed state", %{cb: cb} do
    for _ <- 1..10, do: assert({:ok, :v} = ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn()))
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "trips on threshold consecutive failures", %{cb: cb} do
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "success between failures resets consecutive failure count", %{cb: cb} do
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    # Non-consecutive — reset
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "open state rejects calls without executing", %{cb: cb} do
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())

    tracker = self()

    assert {:error, :circuit_open} =
             ProgressiveRecoveryCircuitBreaker.call(cb, fn ->
               send(tracker, :was_called)
               {:ok, :v}
             end)

    refute_received :was_called
  end

  # -------------------------------------------------------
  # The defining behavior: probe success → :recovering (not :closed)
  # -------------------------------------------------------

  test "successful probe enters :recovering, not :closed directly", %{cb: cb} do
    trip_to_half_open(cb)

    assert {:ok, :v} = ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "probe failure → :open with restarted reset timeout", %{cb: cb} do
    trip_to_half_open(cb)

    assert {:error, :f} = ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Reset timer restarts from the new :open transition, not from original
    Clock.advance(500)
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
    Clock.advance(500)
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Progressive recovery path — the full ladder
  # -------------------------------------------------------

  test "clears every recovery stage → :closed", %{cb: cb} do
    trip_to_half_open(cb)
    # Probe → recovering (stage 0)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 0: 3 calls, 0 failures tolerated
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 1: 5 calls, 1 failure tolerated
    for _ <- 1..5, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 2: 10 calls, 2 failures tolerated → final stage → :closed
    for _ <- 1..10, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "failure within stage tolerance stays in stage", %{cb: cb} do
    trip_to_half_open(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Clear stage 0 (3 calls, 0 failures)
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Now in stage 1: 5 calls, 1 failure tolerated
    # 2 successes + 1 failure = stage_calls=3, stage_failures=1, still under limit
    for _ <- 1..2, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # 2 more successes: stage_calls=5, advance to stage 2
    for _ <- 1..2, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "failure in stage 0 exceeds tolerance → :open", %{cb: cb} do
    trip_to_half_open(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Stage 0 tolerates 0 failures — a single error bounces back to :open
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "second failure in stage 1 exceeds tolerance → :open", %{cb: cb} do
    trip_to_half_open(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    # Clear stage 0
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Stage 1: 1 failure is fine, 2 is too many
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "reopening from :recovering restarts reset timeout", %{cb: cb} do
    trip_to_half_open(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Trigger recovery failure → :open
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Reset timer must be fresh (1s), not carried over
    Clock.advance(500)
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
    Clock.advance(500)
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Exception handling
  # -------------------------------------------------------

  test "raised exception is a failure and doesn't crash the GenServer", %{cb: cb} do
    raise_fn = fn -> raise "boom" end

    assert {:error, %RuntimeError{message: "boom"}} =
             ProgressiveRecoveryCircuitBreaker.call(cb, raise_fn)

    pid = Process.whereis(cb)
    assert Process.alive?(pid)

    # 2 more raises (threshold=3) → trip
    for _ <- 1..2, do: ProgressiveRecoveryCircuitBreaker.call(cb, raise_fn)
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "raised exception in :recovering counts as a stage failure", %{cb: cb} do
    trip_to_half_open(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    # Stage 0: zero tolerance

    assert {:error, %RuntimeError{}} =
             ProgressiveRecoveryCircuitBreaker.call(cb, fn -> raise "boom" end)

    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Manual reset
  # -------------------------------------------------------

  test "reset returns to :closed from :open", %{cb: cb} do
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)

    ProgressiveRecoveryCircuitBreaker.reset(cb)
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "reset returns to :closed from :recovering and clears stage counters", %{cb: cb} do
    trip_to_half_open(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    # Advance into stage 1 with some progress
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..2, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    ProgressiveRecoveryCircuitBreaker.reset(cb)
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)

    # After reset, failure count should be fresh — need full 3 consecutive
    # failures to trip again (not some leftover count).
    for _ <- 1..2, do: ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Helpers for the default-configuration tests below
  # -------------------------------------------------------

  # Starts an extra breaker under a process-unique name, defaulting every
  # option except the injected clock (so documented defaults are exercised).
  defp start_cb(opts) do
    name = :"prcb_#{System.pid()}_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      ProgressiveRecoveryCircuitBreaker.start_link(
        Keyword.merge([name: name, clock: &Clock.now/0], opts)
      )

    name
  end

  defp repeat_call(cb, n, func) do
    for _ <- 1..n, do: ProgressiveRecoveryCircuitBreaker.call(cb, func)
    :ok
  end

  # Default breaker (threshold 5, reset 30_000ms, 1 probe) driven into
  # :recovering at stage 0 of the default ladder.
  defp default_cb_in_recovering do
    cb = start_cb([])
    repeat_call(cb, 5, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
    Clock.advance(30_000)
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)
    assert {:ok, :v} = ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)
    cb
  end

  # -------------------------------------------------------
  # Documented defaults
  # -------------------------------------------------------

  test "default failure_threshold trips only on the 5th consecutive failure" do
    cb = start_cb([])

    repeat_call(cb, 4, err_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)

    assert {:error, :f} = ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "default reset timeout is 30_000ms and the default single probe is allowed" do
    cb = start_cb([])
    repeat_call(cb, 5, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)

    Clock.advance(29_999)
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)

    Clock.advance(1)
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)

    # half_open_max_probes defaults to 1 — the probe must be let through.
    assert {:ok, :v} = ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "default stage 0 tolerates zero failures" do
    cb = default_cb_in_recovering()

    assert {:error, :f} = ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "default ladder: stage 0 needs 5 calls, stage 1 needs 15 with 1 failure tolerated" do
    cb = default_cb_in_recovering()

    # 4 of the 5 calls required by stage 0 — stage not cleared yet.
    repeat_call(cb, 4, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # 5th call clears stage 0 → stage 1 ({15, 1}).
    assert {:ok, :v} = ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 1 tolerates exactly 1 failure (a stage-0 zero tolerance here
    # would have reopened the circuit).
    assert {:error, :f} = ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # 1 failure + 13 successes = 14 of the 15 calls stage 1 requires.
    repeat_call(cb, 13, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # The 15th call is a 2nd failure → exceeds stage 1 tolerance → :open.
    assert {:error, :f} = ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "default final stage needs 30 calls and tolerates 2 failures before closing" do
    cb = default_cb_in_recovering()

    repeat_call(cb, 5, ok_fn())
    repeat_call(cb, 15, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 2 ({30, 2}): two failures are within tolerance.
    repeat_call(cb, 2, err_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # 2 failures + 27 successes = 29 of the 30 required calls — not closed yet.
    repeat_call(cb, 27, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # The 30th call clears the final stage → :closed.
    assert {:ok, :v} = ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "closing via full recovery leaves a zeroed consecutive failure count" do
    cb = default_cb_in_recovering()

    repeat_call(cb, 5, ok_fn())
    repeat_call(cb, 15, ok_fn())
    repeat_call(cb, 30, ok_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)

    # A full 5 consecutive failures must be needed again, not fewer.
    repeat_call(cb, 4, err_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)

    assert {:error, :f} = ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Probe budget and outcome classification
  # -------------------------------------------------------

  test "half-open lets no calls through when the probe budget is zero" do
    cb =
      start_cb(
        failure_threshold: 3,
        reset_timeout_ms: 1_000,
        half_open_max_probes: 0,
        recovery_stages: [{3, 0}]
      )

    repeat_call(cb, 3, err_fn())
    Clock.advance(1_000)
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)

    tracker = self()

    assert {:error, :circuit_open} =
             ProgressiveRecoveryCircuitBreaker.call(cb, fn ->
               send(tracker, :was_called)
               {:ok, :v}
             end)

    refute_received :was_called
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "an unexpected return shape counts as a failure in closed state" do
    # TODO
  end

  test "stage failure counter resets when advancing to the next stage", %{cb: cb} do
    trip_to_half_open(cb)
    # Probe success → recovering stage 0.
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Clear stage 0 {3, 0}: three clean successes → advance to stage 1.
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 1 {5, 1}: one tolerated failure then four successes → 5 calls → stage 2.
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    for _ <- 1..4, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 2 {10, 2}: two failures must be tolerated afresh. If the stage-1
    # failure carried over, 1 + 2 = 3 > 2 would reopen the circuit.
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "re-probe after reopening from a later stage restarts recovery at stage 0", %{cb: cb} do
    trip_to_half_open(cb)
    # Probe success → recovering stage 0.
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Clear stage 0 {3, 0} → now in stage 1 {5, 1}.
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Exceed stage 1 tolerance (2 failures) → :open, from a deep stage.
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Back to half-open; a fresh probe success must restart recovery at stage 0.
    Clock.advance(1_000)
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 0 tolerates zero failures — a single failure reopens. If recovery
    # had resumed at stage 1 (tolerates 1), this failure would be tolerated.
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "an unexpected return shape is passed through to the caller verbatim", %{cb: cb} do
    # It still counts as a failure for the breaker's bookkeeping, but the
    # reply contract holds: the caller sees exactly what func returned.
    assert :not_a_result = ProgressiveRecoveryCircuitBreaker.call(cb, fn -> :not_a_result end)
  end
end
```
