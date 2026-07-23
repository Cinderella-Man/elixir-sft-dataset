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

Hey — I need you to build me an Elixir GenServer module called `RollingRateCircuitBreaker`. It's the circuit breaker pattern, but here's the twist: instead of tripping on a consecutive failure count, I want it to trip based on the error rate over a rolling window of recent calls.

The reason I care about this: a consecutive-count breaker won't trip on a service that alternates success/failure 50/50, even though such a service is clearly unhealthy. Tracking a rolling window of outcomes and tripping on error rate is the approach used by Netflix Hystrix and similar production breakers. A single success in the middle of a stream of failures shouldn't reset the failure record.

The three states are the same as a standard circuit breaker: closed (normal), open (fail fast), half-open (cautious probing). Only the trip decision changes. Keep it a single file with no external dependencies.

Let me walk you through the API.

For `RollingRateCircuitBreaker.start_link(opts)` — this starts and registers the breaker. The options I need it to accept: `:name` is the **required** process registration name, and if it's absent I want it to raise (treat it as a missing required key, not a graceful error tuple). `:window_size` is the number of most recent call outcomes to retain, with older outcomes evicted, defaulting to `20`. `:error_rate_threshold` is a float in `(0.0, 1.0]`, defaulting to `0.5`. `:min_calls_in_window` is the minimum number of outcomes currently in the window before the rate is evaluated at all, defaulting to `10`. `:reset_timeout_ms` is how long the breaker stays open before it's eligible to become half-open, defaulting to `30_000`. `:half_open_max_probes` is the number of probes admitted while half-open, defaulting to `1`. And `:clock` is a zero-arity function returning the current time in milliseconds, defaulting to `fn -> System.monotonic_time(:millisecond) end` — this is the *only* time source the module uses; there are no `Process.send_after` timers, so an injected clock fully controls the breaker's notion of time. Unknown options should just be ignored. The breaker starts in `:closed` with an empty outcome window.

Now for `RollingRateCircuitBreaker.call(name, func)` — `func` is a zero-arity function. Calls are serialized through the GenServer and `func` runs inside the breaker process.

On outcome classification and the return value: the breaker classifies each execution as a success or a failure, and the caller gets back the following. When `func` returns `{:ok, value}`, that's a success and `call/2` returns that exact `{:ok, value}` tuple, unchanged. When `func` returns `{:error, reason}`, that's a failure and `call/2` returns that exact `{:error, reason}` tuple, unchanged. When `func` returns anything else (e.g. `:ok`, `42`, `nil`), that's a failure and `call/2` returns `{:error, {:unexpected_return, other}}` where `other` is the raw value. And when `func` raises an exception, that's a failure and `call/2` returns `{:error, exception_struct}` — the rescued exception struct itself; the GenServer must not crash.

In the closed state: execute `func`, prepend its outcome to the rolling window (window keeps at most `window_size` outcomes, newest first, oldest evicted), then re-evaluate the trip condition against the *post-append* window. The rule is: trip when `total >= min_calls_in_window` **and** `error_count / total >= error_rate_threshold`, where `total` is the number of outcomes currently in the window (never more than `window_size`). Both comparisons are inclusive: exactly `min_calls_in_window` outcomes is enough evidence, and a rate exactly equal to `error_rate_threshold` trips. `total == 0` never trips. If `min_calls_in_window > window_size` the window can never reach the floor, so the breaker never trips on its own — that combination is legal and simply disables automatic tripping. On trip: state becomes `:open`, the moment of tripping is stamped from `:clock`, and the window is emptied. The caller still receives the result of the `func` call that caused the trip (the tripping call is not swallowed).

In the open state: return `{:error, :circuit_open}` immediately without executing `func`. No outcome is recorded.

For the open → half-open transition: there is no timer. Every `call/2` and every `state/1` first checks, when the breaker is open, whether `clock.() - opened_at >= reset_timeout_ms`; if so the breaker transitions to `:half_open` (probe counter zeroed) *before* the request is handled. The boundary is inclusive: elapsed time exactly equal to `reset_timeout_ms` is enough. Because the check is lazy, a breaker whose timeout has elapsed but which nobody has called is still internally open — the very next `call/2` or `state/1` observes and performs the transition.

In the half-open state: up to `half_open_max_probes` probes may be in flight; a call arriving when the in-flight probe count is already at the maximum returns `{:error, :circuit_open}` without executing `func`. Otherwise the probe executes and resolves the state immediately. A probe classified as success → state becomes `:closed`, window emptied, probe counter zeroed. A probe classified as failure → state becomes `:open`, the open timestamp is re-stamped from `:clock` (the reset timeout restarts from the failed probe, not from the original trip), window emptied, probe counter zeroed. Note the consequence of serialized calls: each probe resolves the state before the next request is handled, so a half-open breaker never actually sees a second concurrent probe. Probe outcomes are *not* appended to the outcome window — the rate rule is a closed-state rule only, and one failed probe re-opens the breaker regardless of `min_calls_in_window`.

For `RollingRateCircuitBreaker.state(name)` — returns `:closed | :open | :half_open`. It performs the open→half-open expiry check I described above (so it can itself be the call that flips an expired open breaker to `:half_open`), but it never executes a probe and never consumes a probe slot.

For `RollingRateCircuitBreaker.reset(name)` — returns `:ok`. From any state, it forces the breaker to `:closed`, empties the outcome window, clears the open timestamp, and zeroes the probe counter. Calling it on an already-closed breaker is not a no-op: it discards whatever failures had accumulated in the window. Repeated calls are idempotent.

One last thing on invariants so it's clear: every state transition wipes the outcome window, so each new state starts with a clean slate — closed → open on trip, half-open → closed on probe success, half-open → open on probe failure, and manual reset. A breaker that has just tripped, just closed from a probe, or just been reset therefore needs a fresh `min_calls_in_window` outcomes before it can trip again.
