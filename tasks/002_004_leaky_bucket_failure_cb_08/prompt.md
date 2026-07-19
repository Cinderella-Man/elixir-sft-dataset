# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `reset` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

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

- `LeakyBucketCircuitBreaker.call(name, func)` — standard circuit breaker semantics. Whenever `func` is actually executed, `call` returns `func`'s own return value unchanged — `{:ok, value}` on a success, `{:error, reason}` on a failing tuple — except on a raised exception, where it catches and returns `{:error, exception_struct}` (the raised exception struct itself, e.g. `{:error, %RuntimeError{message: "boom"}}`). In `:closed`:
  1. First apply the leak since the last update: `leak = elapsed_ms * leak_rate_per_sec / 1000`, then `bucket_level = max(0.0, bucket_level - leak)`, and advance `last_update_at` to now.
  2. Execute `func`.
  3. On failure, add `failure_weight` drops to the bucket. On success, do nothing to the bucket.
  4. If the bucket level has reached `bucket_capacity` (i.e. `>=`), transition to `:open` (reset the bucket to 0 on trip so the probe-cycle starts fresh).

  In `:open`, return `{:error, :circuit_open}` immediately without executing `func`. Transition to `:half_open` once `reset_timeout_ms` has elapsed (`>=`); this transition is lazy — a call to `state/1` after the timeout must itself report `:half_open` with no intervening `call`. In `:half_open`, allow up to `half_open_max_probes` calls through — a successful probe returns to `:closed` with an empty bucket; a failed probe returns to `:open` and restarts the reset timeout.

- `LeakyBucketCircuitBreaker.state(name)` returns `:closed | :open | :half_open`.

- `LeakyBucketCircuitBreaker.reset(name)` manually resets to `:closed` with an empty bucket.

- `LeakyBucketCircuitBreaker.bucket_level(name)` — inspection API that returns the current leak-adjusted bucket level as a float. This is useful for metrics and debugging. It must apply the pending leak before returning (so the caller always sees a fresh value).

Outcome classification: `{:ok, value}` is a success; `{:error, reason}` or a raised exception is a failure; any other return shape is a failure. On raise, catch and return `{:error, exception_struct}` without crashing the GenServer.

The leak computation must happen lazily on every call that touches the bucket (not via a periodic timer). All bucket arithmetic should be in floats — integer options like `bucket_capacity: 5` should still work and must be coerced.

Single file, no external dependencies.

## The module with `reset` missing

```elixir
defmodule LeakyBucketCircuitBreaker do
  @moduledoc """
  A circuit breaker that tracks failures using a leaky bucket rather than
  a consecutive-failure counter.

  Each failure adds `failure_weight` drops to the bucket; successes don't
  touch it.  Drops leak out continuously at `leak_rate_per_sec`.  On every
  call that touches the bucket, the leak is applied lazily — the bucket
  level at time `t` is `max(0.0, last_level - (t - last_update_at) * leak_rate_per_sec / 1000)`,
  and `last_update_at` is advanced to `t`.  When the bucket level reaches
  `bucket_capacity`, the breaker trips to `:open`.

  This distinguishes burst failures (fill faster than they leak → trip) from
  sustained low-rate background noise (leak faster than fill → stay closed),
  which a consecutive-count breaker can't do.

  ## Options

    * `:name`                  – required registered name
    * `:bucket_capacity`       – trip threshold (default 5.0)
    * `:leak_rate_per_sec`     – drops leaking per second (default 1.0)
    * `:failure_weight`        – drops added per failure (default 1.0)
    * `:reset_timeout_ms`      – open → half_open delay (default 30_000)
    * `:half_open_max_probes`  – probes allowed in half_open (default 1)
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

  @doc "Runs `func` through the leaky-bucket breaker; result or `{:error, :circuit_open}`."
  @spec call(GenServer.server(), (-> any())) :: any()
  def call(name, func) when is_function(func, 0) do
    GenServer.call(name, {:call, func})
  end

  @spec state(GenServer.server()) :: :closed | :open | :half_open
  def state(name), do: GenServer.call(name, :get_state)

  def reset(name) do
    # TODO
  end

  @spec bucket_level(GenServer.server()) :: float()
  def bucket_level(name), do: GenServer.call(name, :bucket_level)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    # Force float math so integer options like `bucket_capacity: 5` work.
    config = %{
      bucket_capacity: Keyword.get(opts, :bucket_capacity, 5.0) * 1.0,
      leak_rate_per_sec: Keyword.get(opts, :leak_rate_per_sec, 1.0) * 1.0,
      failure_weight: Keyword.get(opts, :failure_weight, 1.0) * 1.0,
      reset_timeout_ms: Keyword.get(opts, :reset_timeout_ms, 30_000),
      half_open_max_probes: Keyword.get(opts, :half_open_max_probes, 1)
    }

    {:ok,
     %{
       state: :closed,
       bucket_level: 0.0,
       last_update_at: clock.(),
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
    {:reply, :ok,
     %{
       state
       | state: :closed,
         bucket_level: 0.0,
         last_update_at: state.clock.(),
         opened_at: nil,
         probes_in_flight: 0
     }}
  end

  def handle_call(:bucket_level, _from, state) do
    state = apply_leak(state)
    {:reply, state.bucket_level, state}
  end

  # ---------------------------------------------------------------------------
  # Per-state execution
  # ---------------------------------------------------------------------------

  defp execute_in_closed(state, func) do
    # Apply leak first so the bucket reflects real time before we evaluate.
    state = apply_leak(state)

    case execute_and_classify(func) do
      {:ok, reply} ->
        # Success doesn't touch the bucket.
        {reply, state}

      {:error, reply} ->
        new_level = state.bucket_level + state.config.failure_weight
        state = %{state | bucket_level: new_level}

        if new_level >= state.config.bucket_capacity do
          # Trip.  Reset bucket so the eventual probe cycle starts clean.
          {reply, %{state | state: :open, opened_at: state.clock.(), bucket_level: 0.0}}
        else
          {reply, state}
        end
    end
  end

  defp execute_in_half_open(state, func) do
    case execute_and_classify(func) do
      {:ok, reply} ->
        # Probe succeeded — fresh bucket, full closure.
        {reply,
         %{
           state
           | state: :closed,
             bucket_level: 0.0,
             last_update_at: state.clock.(),
             opened_at: nil,
             probes_in_flight: 0
         }}

      {:error, reply} ->
        {reply, %{state | state: :open, opened_at: state.clock.(), probes_in_flight: 0}}
    end
  end

  # ---------------------------------------------------------------------------
  # Leak computation — the heart of the algorithm
  # ---------------------------------------------------------------------------

  # Lazily subtract the leak accumulated since the last update, clamped at 0,
  # and advance `last_update_at` to now.
  defp apply_leak(state) do
    now = state.clock.()
    elapsed_ms = now - state.last_update_at
    leak = elapsed_ms * state.config.leak_rate_per_sec / 1000
    new_level = max(0.0, state.bucket_level - leak)
    %{state | bucket_level: new_level, last_update_at: now}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

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
end
```

Give me only the complete implementation of `reset` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
