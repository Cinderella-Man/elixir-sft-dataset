# One bug. Find it. Fix it.

The module below implements the task that follows, except for a single
behavior bug. The bottom of this prompt shows the real failure report from
its (hidden) test suite. Deliver the full corrected module: smallest
possible change, no restructuring, nothing else touched.

## Target behavior

Write me an Elixir GenServer module called `RollingRateCircuitBreaker` that implements the circuit breaker pattern, but trips based on **error rate over a rolling window of recent calls** instead of consecutive failure count.

The motivation: a consecutive-count breaker won't trip on a service that alternates success/failure 50/50, even though such a service is clearly unhealthy. Tracking a rolling window of outcomes and tripping on error rate is the approach used by Netflix Hystrix and similar production breakers. A single success in the middle of a stream of failures shouldn't reset the failure record.

The three states are the same as a standard circuit breaker: closed (normal), open (fail fast), half-open (cautious probing). Only the trip decision changes.

Single file, no external dependencies.

## API

### `RollingRateCircuitBreaker.start_link(opts)`

Starts and registers the breaker. Options:

- `:name` — **required** process registration name. Absent → raise (a missing required key, not a graceful error tuple).
- `:window_size` — number of most recent call outcomes to retain; older outcomes are evicted. Default `20`.
- `:error_rate_threshold` — float in `(0.0, 1.0]`. Default `0.5`.
- `:min_calls_in_window` — minimum number of outcomes currently in the window before the rate is evaluated at all. Default `10`.
- `:reset_timeout_ms` — how long the breaker stays open before it is eligible to become half-open. Default `30_000`.
- `:half_open_max_probes` — probes admitted while half-open. Default `1`.
- `:clock` — zero-arity function returning the current time in milliseconds. Default `fn -> System.monotonic_time(:millisecond) end`. This is the *only* time source the module uses; there are no `Process.send_after` timers, so an injected clock fully controls the breaker's notion of time.

Unknown options are ignored. The breaker starts in `:closed` with an empty outcome window.

### `RollingRateCircuitBreaker.call(name, func)`

`func` is a zero-arity function. Calls are serialized through the GenServer and `func` runs inside the breaker process.

**Outcome classification and return value.** The breaker classifies each execution as a success or a failure, and the caller gets back:

| `func` does | classified as | `call/2` returns |
|---|---|---|
| returns `{:ok, value}` | success | that exact `{:ok, value}` tuple, unchanged |
| returns `{:error, reason}` | failure | that exact `{:error, reason}` tuple, unchanged |
| returns anything else (e.g. `:ok`, `42`, `nil`) | failure | `{:error, {:unexpected_return, other}}` where `other` is the raw value |
| raises an exception | failure | `{:error, exception_struct}` — the rescued exception struct itself; the GenServer must not crash |

**Closed state.** Execute `func`, prepend its outcome to the rolling window (window keeps at most `window_size` outcomes, newest first, oldest evicted), then re-evaluate the trip condition against the *post-append* window:

> trip when `total >= min_calls_in_window` **and** `error_count / total >= error_rate_threshold`, where `total` is the number of outcomes currently in the window (never more than `window_size`).

Both comparisons are inclusive: exactly `min_calls_in_window` outcomes is enough evidence, and a rate exactly equal to `error_rate_threshold` trips. `total == 0` never trips. If `min_calls_in_window > window_size` the window can never reach the floor, so the breaker never trips on its own — that combination is legal and simply disables automatic tripping.

On trip: state becomes `:open`, the moment of tripping is stamped from `:clock`, and the window is emptied. The caller still receives the result of the `func` call that caused the trip (the tripping call is not swallowed).

**Open state.** Return `{:error, :circuit_open}` immediately without executing `func`. No outcome is recorded.

**Open → half-open.** There is no timer. Every `call/2` and every `state/1` first checks, when the breaker is open, whether `clock.() - opened_at >= reset_timeout_ms`; if so the breaker transitions to `:half_open` (probe counter zeroed) *before* the request is handled. The boundary is inclusive: elapsed time exactly equal to `reset_timeout_ms` is enough. Because the check is lazy, a breaker whose timeout has elapsed but which nobody has called is still internally open — the very next `call/2` or `state/1` observes and performs the transition.

**Half-open state.** Up to `half_open_max_probes` probes may be in flight; a call arriving when the in-flight probe count is already at the maximum returns `{:error, :circuit_open}` without executing `func`. Otherwise the probe executes and resolves the state immediately:

- probe classified as success → state becomes `:closed`, window emptied, probe counter zeroed.
- probe classified as failure → state becomes `:open`, the open timestamp is re-stamped from `:clock` (the reset timeout restarts from the failed probe, not from the original trip), window emptied, probe counter zeroed.

Note the consequence of serialized calls: each probe resolves the state before the next request is handled, so a half-open breaker never actually sees a second concurrent probe. Probe outcomes are *not* appended to the outcome window — the rate rule is a closed-state rule only, and one failed probe re-opens the breaker regardless of `min_calls_in_window`.

### `RollingRateCircuitBreaker.state(name)`

Returns `:closed | :open | :half_open`. It performs the open→half-open expiry check described above (so it can itself be the call that flips an expired open breaker to `:half_open`), but it never executes a probe and never consumes a probe slot.

### `RollingRateCircuitBreaker.reset(name)`

Returns `:ok`. From any state, forces the breaker to `:closed`, empties the outcome window, clears the open timestamp, and zeroes the probe counter. Calling it on an already-closed breaker is not a no-op: it discards whatever failures had accumulated in the window. Repeated calls are idempotent.

## Invariants

Every state transition wipes the outcome window, so each new state starts with a clean slate: closed → open on trip, half-open → closed on probe success, half-open → open on probe failure, and manual reset. A breaker that has just tripped, just closed from a probe, or just been reset therefore needs a fresh `min_calls_in_window` outcomes before it can trip again.

## The buggy module

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

      false ->
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

## Failing test report

```
12 of 12 test(s) failed:

  * test passes through successes without tripping
      {:EXIT, #PID<0.210.0>}: {:cond_clause, [{RollingRateCircuitBreaker, :should_trip?, 2, [file: ~c".gen_staging/bugfix_002_002_rolling_window_error_rate_cb_02_mutant.ex", line: 172]}, {RollingRateCircuitBreaker, :execute_in_closed, 2, [file: ~c".gen_staging/bugfix_002_002_rolling_window_error_rate_cb_02_mutant.ex", line: 126]}, {RollingRateCircuitBreaker, :handle_call, 3, [file: ~c".gen_staging/bugfix_002_002_rolling_window_error_rate_cb_02_mutant.ex", line: 89]}, {:gen_server, :try_handle_call, 4,

  * test does not trip when error rate is below threshold
      {:EXIT, #PID<0.214.0>}: {:cond_clause, [{RollingRateCircuitBreaker, :should_trip?, 2, [file: ~c".gen_staging/bugfix_002_002_rolling_window_error_rate_cb_02_mutant.ex", line: 172]}, {RollingRateCircuitBreaker, :execute_in_closed, 2, [file: ~c".gen_staging/bugfix_002_002_rolling_window_error_rate_cb_02_mutant.ex", line: 126]}, {RollingRateCircuitBreaker, :handle_call, 3, [file: ~c".gen_staging/bugfix_002_002_rolling_window_error_rate_cb_02_mutant.ex", line: 89]}, {:gen_server, :try_handle_call, 4,

  * test trips when error rate reaches threshold and min calls are met
      {:EXIT, #PID<0.218.0>}: {:cond_clause, [{RollingRateCircuitBreaker, :should_trip?, 2, [file: ~c".gen_staging/bugfix_002_002_rolling_window_error_rate_cb_02_mutant.ex", line: 172]}, {RollingRateCircuitBreaker, :execute_in_closed, 2, [file: ~c".gen_staging/bugfix_002_002_rolling_window_error_rate_cb_02_mutant.ex", line: 126]}, {RollingRateCircuitBreaker, :handle_call, 3, [file: ~c".gen_staging/bugfix_002_002_rolling_window_error_rate_cb_02_mutant.ex", line: 89]}, {:gen_server, :try_handle_call, 4,

  * test does not trip when error rate is high but min_calls not met
      {:EXIT, #PID<0.222.0>}: {:cond_clause, [{RollingRateCircuitBreaker, :should_trip?, 2, [file: ~c".gen_staging/bugfix_002_002_rolling_window_error_rate_cb_02_mutant.ex", line: 172]}, {RollingRateCircuitBreaker, :execute_in_closed, 2, [file: ~c".gen_staging/bugfix_002_002_rolling_window_error_rate_cb_02_mutant.ex", line: 126]}, {RollingRateCircuitBreaker, :handle_call, 3, [file: ~c".gen_staging/bugfix_002_002_rolling_window_error_rate_cb_02_mutant.ex", line: 89]}, {:gen_server, :try_handle_call, 4,

  (…8 more)
```
