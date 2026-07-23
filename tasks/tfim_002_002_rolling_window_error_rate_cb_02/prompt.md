# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule RollingRateCircuitBreaker do
  @moduledoc """
  A GenServer-based circuit breaker that trips on error rate over a rolling
  window of the most recent N calls, rather than on consecutive failures.

  The window is count-based: every call's outcome (`:ok` or `:error`) is
  prepended to the list, and the tail beyond `window_size` is dropped.  On
  every call in the closed state, the trip condition is re-evaluated:

      error_count / total_count >= error_rate_threshold
      AND total_count >= min_calls_in_window

  The `min_calls_in_window` floor prevents a single early failure (1/1 = 100%)
  from tripping the breaker before enough evidence has accumulated.

  Every state transition wipes the outcome window so the new state starts
  with fresh evidence.

  ## Options

    * `:name`                    – required process registration name
    * `:window_size`             – rolling window size (default 20)
    * `:error_rate_threshold`    – trip threshold, `(0.0, 1.0]` (default 0.5)
    * `:min_calls_in_window`     – minimum calls before evaluating rate (default 10)
    * `:reset_timeout_ms`        – open → half_open delay (default 30_000)
    * `:half_open_max_probes`    – probes allowed in half_open (default 1)
    * `:clock`                   – `(-> integer())` current time in ms

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

  @doc "Runs `func` through the breaker; returns its result or `{:error, :circuit_open}`."
  @spec call(GenServer.server(), (-> any())) :: any()
  def call(name, func) when is_function(func, 0) do
    GenServer.call(name, {:call, func})
  end

  @spec state(GenServer.server()) :: :closed | :open | :half_open
  def state(name), do: GenServer.call(name, :get_state)

  @spec reset(GenServer.server()) :: :ok
  def reset(name), do: GenServer.call(name, :reset)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    config = %{
      window_size: Keyword.get(opts, :window_size, 20),
      error_rate_threshold: Keyword.get(opts, :error_rate_threshold, 0.5),
      min_calls_in_window: Keyword.get(opts, :min_calls_in_window, 10),
      reset_timeout_ms: Keyword.get(opts, :reset_timeout_ms, 30_000),
      half_open_max_probes: Keyword.get(opts, :half_open_max_probes, 1)
    }

    {:ok,
     %{
       state: :closed,
       # outcomes are :ok or :error atoms, newest first, max length window_size
       outcomes: [],
       opened_at: nil,
       probes_in_flight: 0,
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
    end
  end

  def handle_call(:get_state, _from, state) do
    state = maybe_expire_open(state)
    {:reply, state.state, state}
  end

  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | state: :closed, outcomes: [], opened_at: nil, probes_in_flight: 0}}
  end

  # ---------------------------------------------------------------------------
  # Execution helpers
  # ---------------------------------------------------------------------------

  defp execute_in_closed(state, func) do
    {outcome, reply} = execute_and_classify(func)

    outcomes =
      [outcome | state.outcomes]
      |> Enum.take(state.config.window_size)

    if should_trip?(outcomes, state.config) do
      {reply,
       %{state | state: :open, opened_at: state.clock.(), outcomes: [], probes_in_flight: 0}}
    else
      {reply, %{state | outcomes: outcomes}}
    end
  end

  defp execute_in_half_open(state, func) do
    case execute_and_classify(func) do
      {:ok, reply} ->
        # Probe succeeded → fully closed, clean slate.
        {reply, %{state | state: :closed, outcomes: [], opened_at: nil, probes_in_flight: 0}}

      {:error, reply} ->
        # Probe failed → open again, restart the reset timer.
        {reply,
         %{state | state: :open, opened_at: state.clock.(), outcomes: [], probes_in_flight: 0}}
    end
  end

  # Runs the user function, classifies the outcome.  Returns `{outcome, reply}`
  # where outcome is `:ok` or `:error` (for window bookkeeping) and reply is
  # the tuple the caller receives.
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

  defp should_trip?(outcomes, config) do
    total = length(outcomes)

    cond do
      total == 0 ->
        false

      total < config.min_calls_in_window ->
        false

      true ->
        errors = Enum.count(outcomes, &(&1 == :error))
        errors / total >= config.error_rate_threshold
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
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule RollingRateCircuitBreakerTest do
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

    {:ok, _pid} =
      RollingRateCircuitBreaker.start_link(
        name: :test_cb,
        window_size: 10,
        error_rate_threshold: 0.5,
        min_calls_in_window: 6,
        reset_timeout_ms: 1_000,
        half_open_max_probes: 1,
        clock: &Clock.now/0
      )

    %{cb: :test_cb}
  end

  defp ok_fn, do: fn -> {:ok, :value} end
  defp err_fn, do: fn -> {:error, :failure} end

  # -------------------------------------------------------
  # Baseline closed behavior
  # -------------------------------------------------------

  test "passes through successes without tripping", %{cb: cb} do
    # TODO
  end

  test "does not trip when error rate is below threshold", %{cb: cb} do
    # 3 errors out of 10 = 30%, below 50% threshold
    for _ <- 1..7, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())

    assert :closed = RollingRateCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Rate-based tripping (the defining property)
  # -------------------------------------------------------

  test "trips when error rate reaches threshold and min calls are met", %{cb: cb} do
    # Window: [:ok, :ok, :ok, :error, :error, :error] → 3/6 = 50% ≥ 0.5
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())

    assert :open = RollingRateCircuitBreaker.state(cb)
  end

  test "does not trip when error rate is high but min_calls not met", %{cb: cb} do
    # 5 errors, 0 successes → 100% error rate, but only 5 calls (min = 6)
    for _ <- 1..5, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)

    # 6th error now meets min_calls AND threshold → trip
    RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)
  end

  test "alternating success/failure trips once threshold is met", %{cb: cb} do
    # Strict 50/50 alternation — would never trip a consecutive-count breaker.
    for _ <- 1..3 do
      RollingRateCircuitBreaker.call(cb, ok_fn())
      RollingRateCircuitBreaker.call(cb, err_fn())
    end

    # Window: 3 errors / 6 total = 50% ≥ 0.5, min_calls met → trip
    assert :open = RollingRateCircuitBreaker.state(cb)
  end

  test "rolling window evicts old outcomes and can un-trip risk as errors age out", %{cb: cb} do
    # Fill window with 10 successes
    for _ <- 1..10, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)

    # Adding 4 errors: window is [4 errors, 6 successes] = 4/10 = 40%, still closed
    for _ <- 1..4, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)

    # One more error: now [5 errors, 5 successes] = 50%, trips.
    RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Open / half-open transitions
  # -------------------------------------------------------

  test "open state rejects calls without executing the function", %{cb: cb} do
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)

    tracker = self()

    assert {:error, :circuit_open} =
             RollingRateCircuitBreaker.call(cb, fn ->
               send(tracker, :was_called)
               {:ok, :wat}
             end)

    refute_received :was_called
  end

  test "open → half_open after reset_timeout_ms", %{cb: cb} do
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)

    Clock.advance(1_000)
    assert :half_open = RollingRateCircuitBreaker.state(cb)
  end

  test "half_open probe success → closed with empty window", %{cb: cb} do
    # Trip, then wait to half-open
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)
    assert :half_open = RollingRateCircuitBreaker.state(cb)

    # Successful probe → closed
    assert {:ok, :value} = RollingRateCircuitBreaker.call(cb, ok_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)

    # Old outcomes are wiped — 3 fresh errors shouldn't trip (below min_calls)
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)
  end

  test "half_open probe failure → open and restarts reset timeout", %{cb: cb} do
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)
    assert :half_open = RollingRateCircuitBreaker.state(cb)

    assert {:error, :failure} = RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)

    # Reset timeout must restart, not carry over
    Clock.advance(500)
    assert :open = RollingRateCircuitBreaker.state(cb)

    Clock.advance(500)
    assert :half_open = RollingRateCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Exception handling
  # -------------------------------------------------------

  test "raised exceptions count as failures and don't crash the GenServer", %{cb: cb} do
    raise_fn = fn -> raise "boom" end

    assert {:error, %RuntimeError{message: "boom"}} =
             RollingRateCircuitBreaker.call(cb, raise_fn)

    pid = Process.whereis(cb)
    assert Process.alive?(pid)

    # 6 raises should meet min_calls at 100% error rate → trip
    for _ <- 1..5, do: RollingRateCircuitBreaker.call(cb, raise_fn)
    assert :open = RollingRateCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Manual reset
  # -------------------------------------------------------

  test "reset returns to closed from any state and clears the window", %{cb: cb} do
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)

    RollingRateCircuitBreaker.reset(cb)
    assert :closed = RollingRateCircuitBreaker.state(cb)

    # Window should be empty — a new burst of errors shouldn't re-trip until
    # min_calls is met again.
    for _ <- 1..5, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Helpers for breakers with non-setup configuration
  # -------------------------------------------------------

  defp unique_name(prefix) do
    :"#{prefix}_#{System.pid()}_#{System.unique_integer([:positive])}"
  end

  # Starts a breaker on the fake clock; `opts` supplies only the options the
  # test cares about, so every other option keeps its documented default.
  defp start_cb(opts) do
    name = unique_name(:cb)

    {:ok, _pid} =
      RollingRateCircuitBreaker.start_link([name: name, clock: &Clock.now/0] ++ opts)

    name
  end

  # -------------------------------------------------------
  # Documented option defaults
  # -------------------------------------------------------

  test "defaults: 10 min_calls, 30_000 ms reset timeout, one half_open probe" do
    cb = start_cb([])

    # Default min_calls_in_window is 10: nine 100%-error calls are not enough
    # evidence, the tenth exactly meets the (inclusive) floor at rate 1.0 ≥ 0.5.
    for _ <- 1..9, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)

    assert {:error, :failure} = RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)

    # Default reset_timeout_ms is 30_000, boundary inclusive.
    Clock.advance(29_999)
    assert :open = RollingRateCircuitBreaker.state(cb)

    Clock.advance(1)
    assert :half_open = RollingRateCircuitBreaker.state(cb)

    # Default half_open_max_probes is 1: exactly one probe is admitted and a
    # successful probe closes the breaker.
    assert {:ok, :value} = RollingRateCircuitBreaker.call(cb, ok_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)
  end

  test "default window_size of 20 evicts the oldest outcome on the 21st call" do
    # Threshold 1.0 means only an all-error window trips, so the lone success
    # pins the exact call on which it is evicted — i.e. the window size.
    cb = start_cb(error_rate_threshold: 1.0, min_calls_in_window: 1)

    assert {:ok, :value} = RollingRateCircuitBreaker.call(cb, ok_fn())

    # 19 errors + that success = 20 outcomes → 19/20 < 1.0, still closed.
    for _ <- 1..19, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)

    # The 21st call evicts the oldest outcome (the success): 20/20 = 1.0 → trip.
    assert {:error, :failure} = RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Boundary conditions of the trip rule
  # -------------------------------------------------------

  test "a single failure trips when min_calls_in_window is 1 and threshold is 1.0" do
    # total (1) >= min_calls_in_window (1) and 1/1 = 1.0 >= 1.0 → trip.
    cb = start_cb(min_calls_in_window: 1, error_rate_threshold: 1.0)

    assert {:error, :failure} = RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)
  end

  test "half_open admits no probe when half_open_max_probes is 0" do
    cb =
      start_cb(
        min_calls_in_window: 1,
        error_rate_threshold: 1.0,
        reset_timeout_ms: 1_000,
        half_open_max_probes: 0
      )

    assert {:error, :failure} = RollingRateCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)
    assert :half_open = RollingRateCircuitBreaker.state(cb)

    tracker = self()

    # In-flight probe count (0) is already at the maximum (0) → fail fast
    # without executing func, and the breaker stays half_open.
    assert {:error, :circuit_open} =
             RollingRateCircuitBreaker.call(cb, fn ->
               send(tracker, :probed)
               {:ok, :value}
             end)

    refute_received :probed
    assert :half_open = RollingRateCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Unexpected return values
  # -------------------------------------------------------

  test "unexpected return values are wrapped and counted as failures", %{cb: cb} do
    assert {:error, {:unexpected_return, :ok}} =
             RollingRateCircuitBreaker.call(cb, fn -> :ok end)

    assert {:error, {:unexpected_return, 42}} = RollingRateCircuitBreaker.call(cb, fn -> 42 end)

    # Six failures at a 100% rate meet min_calls (6) and the 0.5 threshold.
    for _ <- 1..4, do: RollingRateCircuitBreaker.call(cb, fn -> nil end)
    assert :open = RollingRateCircuitBreaker.state(cb)
  end

  test "call/2 on an expired open breaker performs the transition and runs a probe", %{cb: cb} do
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)

    # Timeout elapses but nobody calls state/1 — call/2 itself must flip and probe.
    Clock.advance(1_000)
    tracker = self()

    assert {:ok, :probed} =
             RollingRateCircuitBreaker.call(cb, fn ->
               send(tracker, :probe_ran)
               {:ok, :probed}
             end)

    assert_received :probe_ran
    assert :closed = RollingRateCircuitBreaker.state(cb)
  end

  test "the tripping call still returns its own func result", %{cb: cb} do
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..2, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)

    # This 6th outcome pushes 3/6 = 0.5 → trip, yet must return the func result.
    assert {:error, :failure} = RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)
  end

  test "min_calls_in_window above window_size disables automatic tripping" do
    cb = start_cb(window_size: 5, min_calls_in_window: 10, error_rate_threshold: 0.5)

    for _ <- 1..30, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)
  end

  test "reset on a closed breaker discards accumulated window failures", %{cb: cb} do
    # 5 errors: below min_calls (6), so still closed but the window is dirty.
    for _ <- 1..5, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)

    assert :ok = RollingRateCircuitBreaker.reset(cb)

    # Had reset been a no-op, 5 + 5 = 10 errors at 100% would have tripped.
    for _ <- 1..5, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)
  end

  test "state on a half_open breaker never consumes the sole probe slot", %{cb: cb} do
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)

    # Repeated state/1 in half_open must not use up the single probe slot.
    assert :half_open = RollingRateCircuitBreaker.state(cb)
    assert :half_open = RollingRateCircuitBreaker.state(cb)
    assert :half_open = RollingRateCircuitBreaker.state(cb)

    tracker = self()

    assert {:ok, :ran} =
             RollingRateCircuitBreaker.call(cb, fn ->
               send(tracker, :probe_ran)
               {:ok, :ran}
             end)

    assert_received :probe_ran
    assert :closed = RollingRateCircuitBreaker.state(cb)
  end

  test "start_link raises when the required name option is absent" do
    assert_raise KeyError, fn ->
      RollingRateCircuitBreaker.start_link(window_size: 5, clock: &Clock.now/0)
    end
  end
end
```
