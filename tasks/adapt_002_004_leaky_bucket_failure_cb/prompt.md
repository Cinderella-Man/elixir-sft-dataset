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

Write me an Elixir GenServer module called `LeakyBucketCircuitBreaker` that tracks failures using a **leaky bucket** instead of a consecutive counter.

The motivation: a consecutive-failure breaker can't distinguish "5 failures in the last second" from "5 failures spread over an hour." The second pattern is benign background noise; the first is an outage. A leaky bucket accumulates failure drops continuously and leaks them at a constant rate, which naturally handles both cases — a burst of failures fills the bucket faster than it can leak (trip), while sustained low-rate failures leak out faster than they arrive (stay closed). The same underlying mechanism is used in networking gear like Cisco routers for error-rate detection.

States are the standard three: closed (normal), open (fail fast), half-open (cautious probing).

API:

- `LeakyBucketCircuitBreaker.start_link(opts)` with options:
  - `:name` — required process registration name
  - `:bucket_capacity` — trip threshold; when bucket level reaches this, transition to `:open` (default 5.0)
  - `:leak_rate_per_sec` — how fast drops leak out, in units per second (default 1.0)
  - `:failure_weight` — drops added to the bucket per failure (default 1.0). Successes don't add anything.
  - `:reset_timeout_ms` — time to stay open before half-open (default 30_000)
  - `:half_open_max_probes` — probes allowed in half-open (default 1)
  - `:clock` — zero-arity function returning current time in milliseconds (default `fn -> System.monotonic_time(:millisecond) end`)

- `LeakyBucketCircuitBreaker.call(name, func)` — standard circuit breaker semantics. In `:closed`:
  1. First apply the leak since the last update: `leak = elapsed_ms * leak_rate_per_sec / 1000`, then `bucket_level = max(0.0, bucket_level - leak)`, and advance `last_update_at` to now.
  2. Execute `func`.
  3. On failure, add `failure_weight` drops to the bucket. On success, do nothing to the bucket.
  4. If the bucket level has reached `bucket_capacity`, transition to `:open` (reset the bucket to 0 on trip so the probe-cycle starts fresh).

  In `:open`, return `{:error, :circuit_open}` immediately. Transition to `:half_open` once `reset_timeout_ms` has elapsed. In `:half_open`, allow up to `half_open_max_probes` calls through — a successful probe returns to `:closed` with an empty bucket; a failed probe returns to `:open`.

- `LeakyBucketCircuitBreaker.state(name)` returns `:closed | :open | :half_open`.

- `LeakyBucketCircuitBreaker.reset(name)` manually resets to `:closed` with an empty bucket.

- `LeakyBucketCircuitBreaker.bucket_level(name)` — inspection API that returns the current leak-adjusted bucket level as a float. This is useful for metrics and debugging. It must apply the pending leak before returning (so the caller always sees a fresh value).

Outcome classification: `{:ok, value}` is a success; `{:error, reason}` or a raised exception is a failure; any other return shape is a failure. On raise, catch and return `{:error, exception_struct}` without crashing the GenServer.

The leak computation must happen lazily on every call that touches the bucket (not via a periodic timer). All bucket arithmetic should be in floats — integer options like `bucket_capacity: 5` should still work and must be coerced.

Single file, no external dependencies.
