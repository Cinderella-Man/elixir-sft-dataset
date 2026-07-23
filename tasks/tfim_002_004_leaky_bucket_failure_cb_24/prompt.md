# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

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

  @spec reset(GenServer.server()) :: :ok
  def reset(name), do: GenServer.call(name, :reset)

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

## Test harness — implement the `# TODO` test

```elixir
defmodule LeakyBucketCircuitBreakerTest do
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
      LeakyBucketCircuitBreaker.start_link(
        name: :test_cb,
        bucket_capacity: 5.0,
        leak_rate_per_sec: 1.0,
        failure_weight: 1.0,
        reset_timeout_ms: 1_000,
        half_open_max_probes: 1,
        clock: &Clock.now/0
      )

    %{cb: :test_cb}
  end

  defp ok_fn, do: fn -> {:ok, :v} end
  defp err_fn, do: fn -> {:error, :f} end

  # -------------------------------------------------------
  # Bucket mechanics
  # -------------------------------------------------------

  test "bucket starts empty", %{cb: cb} do
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end

  test "each failure adds failure_weight to bucket", %{cb: cb} do
    LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert 1.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert 2.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert 3.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end

  test "successes do not add to bucket", %{cb: cb} do
    for _ <- 1..20, do: LeakyBucketCircuitBreaker.call(cb, ok_fn())
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end

  test "bucket leaks at leak_rate_per_sec", %{cb: cb} do
    for _ <- 1..3, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert 3.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    # 1 second elapsed — leak 1.0 drop
    Clock.advance(1_000)
    assert 2.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    # 2 more seconds — leaks to 0
    Clock.advance(2_000)
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end

  test "bucket never goes below zero even after long idle", %{cb: cb} do
    Clock.advance(1_000_000)
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert 1.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end

  test "partial-second leak works correctly", %{cb: cb} do
    for _ <- 1..3, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    # 500ms at 1.0 drops/sec = 0.5 leaked
    Clock.advance(500)
    assert 2.5 = LeakyBucketCircuitBreaker.bucket_level(cb)
  end

  # -------------------------------------------------------
  # Tripping behavior — the defining property
  # -------------------------------------------------------

  test "trips when bucket reaches capacity (burst)", %{cb: cb} do
    # 5 failures in quick succession fills the bucket to capacity
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert :open = LeakyBucketCircuitBreaker.state(cb)
  end

  test "does not trip when failure rate is outpaced by leak rate", %{cb: cb} do
    # One failure every 2 seconds, leak rate is 1/sec → bucket oscillates ≤ 1.0
    for _ <- 1..20 do
      LeakyBucketCircuitBreaker.call(cb, err_fn())
      Clock.advance(2_000)
    end

    assert :closed = LeakyBucketCircuitBreaker.state(cb)
  end

  test "trips on burst even after a long quiet period leaks the bucket empty", %{cb: cb} do
    # Earn some drops, then wait long enough for the bucket to empty
    for _ <- 1..2, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    Clock.advance(10_000)
    # Bucket should be at 0 now
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    # Fresh burst fills the bucket to capacity and trips
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert :open = LeakyBucketCircuitBreaker.state(cb)
  end

  test "intermingled successes don't reset the bucket", %{cb: cb} do
    # Unlike a consecutive-count breaker, successes here don't reduce the bucket.
    # 4 failures + a success + 1 more failure should still trip.
    for _ <- 1..4, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    LeakyBucketCircuitBreaker.call(cb, ok_fn())
    assert :closed = LeakyBucketCircuitBreaker.state(cb)
    assert 4.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert :open = LeakyBucketCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Custom weights
  # -------------------------------------------------------

  test "failure_weight scales how many drops each failure adds", %{cb: _cb} do
    # REMOVED: start_supervised!({Clock, 0})

    {:ok, _pid} =
      LeakyBucketCircuitBreaker.start_link(
        name: :weighted_cb,
        bucket_capacity: 10.0,
        leak_rate_per_sec: 1.0,
        failure_weight: 3.0,
        reset_timeout_ms: 1_000,
        clock: &Clock.now/0
      )

    # 3 failures = 9 drops, still under 10
    for _ <- 1..3, do: LeakyBucketCircuitBreaker.call(:weighted_cb, err_fn())
    assert 9.0 == LeakyBucketCircuitBreaker.bucket_level(:weighted_cb)

    # 4th failure → 12 drops, trips
    LeakyBucketCircuitBreaker.call(:weighted_cb, err_fn())
    assert :open == LeakyBucketCircuitBreaker.state(:weighted_cb)
  end

  test "integer options are coerced to floats", %{cb: _cb} do
    # REMOVED: start_supervised!({Clock, 0})

    # All integer options — should still work
    {:ok, _pid} =
      LeakyBucketCircuitBreaker.start_link(
        name: :int_cb,
        bucket_capacity: 3,
        leak_rate_per_sec: 2,
        failure_weight: 1,
        reset_timeout_ms: 1_000,
        clock: &Clock.now/0
      )

    for _ <- 1..3, do: LeakyBucketCircuitBreaker.call(:int_cb, err_fn())
    assert :open == LeakyBucketCircuitBreaker.state(:int_cb)
  end

  # -------------------------------------------------------
  # State transitions
  # -------------------------------------------------------

  test "open state rejects calls without executing", %{cb: cb} do
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())

    tracker = self()

    assert {:error, :circuit_open} =
             LeakyBucketCircuitBreaker.call(cb, fn ->
               send(tracker, :was_called)
               {:ok, :v}
             end)

    refute_received :was_called
  end

  test "open → half_open after reset_timeout_ms", %{cb: cb} do
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)
    assert :half_open = LeakyBucketCircuitBreaker.state(cb)
  end

  test "probe success → :closed with empty bucket", %{cb: cb} do
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)

    assert {:ok, :v} = LeakyBucketCircuitBreaker.call(cb, ok_fn())
    assert :closed = LeakyBucketCircuitBreaker.state(cb)
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    # Fresh bucket — can tolerate some new failures without tripping
    for _ <- 1..4, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert :closed = LeakyBucketCircuitBreaker.state(cb)
  end

  test "probe failure → :open with restarted reset timeout", %{cb: cb} do
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)

    assert {:error, :f} = LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert :open = LeakyBucketCircuitBreaker.state(cb)

    Clock.advance(500)
    assert :open = LeakyBucketCircuitBreaker.state(cb)
    Clock.advance(500)
    assert :half_open = LeakyBucketCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Exception handling
  # -------------------------------------------------------

  test "raised exceptions count as failures and don't crash the GenServer", %{cb: cb} do
    raise_fn = fn -> raise "boom" end

    assert {:error, %RuntimeError{message: "boom"}} =
             LeakyBucketCircuitBreaker.call(cb, raise_fn)

    pid = Process.whereis(cb)
    assert Process.alive?(pid)

    # 4 more raises fill the bucket and trip
    for _ <- 1..4, do: LeakyBucketCircuitBreaker.call(cb, raise_fn)
    assert :open = LeakyBucketCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Manual reset
  # -------------------------------------------------------

  test "reset clears the bucket and returns to :closed", %{cb: cb} do
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert :open = LeakyBucketCircuitBreaker.state(cb)

    LeakyBucketCircuitBreaker.reset(cb)
    assert :closed = LeakyBucketCircuitBreaker.state(cb)
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end

  test "reset from :closed with partial bucket clears it", %{cb: cb} do
    for _ <- 1..3, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert 3.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    LeakyBucketCircuitBreaker.reset(cb)
    assert :closed = LeakyBucketCircuitBreaker.state(cb)
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end

  test "an unexpected return shape counts as a failure and fills the bucket", %{cb: cb} do
    weird = fn -> :not_a_tuple end
    LeakyBucketCircuitBreaker.call(cb, weird)
    assert 1.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    for _ <- 1..4, do: LeakyBucketCircuitBreaker.call(cb, weird)
    assert :open = LeakyBucketCircuitBreaker.state(cb)
  end

  test "default bucket_capacity of 5.0 trips on the fifth failure", %{cb: _cb} do
    {:ok, _pid} =
      LeakyBucketCircuitBreaker.start_link(
        name: :default_cap_cb,
        leak_rate_per_sec: 1.0,
        failure_weight: 1.0,
        reset_timeout_ms: 1_000,
        clock: &Clock.now/0
      )

    for _ <- 1..4, do: LeakyBucketCircuitBreaker.call(:default_cap_cb, err_fn())
    assert :closed = LeakyBucketCircuitBreaker.state(:default_cap_cb)

    LeakyBucketCircuitBreaker.call(:default_cap_cb, err_fn())
    assert :open = LeakyBucketCircuitBreaker.state(:default_cap_cb)
  end

  test "default reset_timeout_ms of 30_000 keeps circuit open until 30s elapse", %{cb: _cb} do
    {:ok, _pid} =
      LeakyBucketCircuitBreaker.start_link(
        name: :default_rt_cb,
        bucket_capacity: 5.0,
        leak_rate_per_sec: 1.0,
        failure_weight: 1.0,
        clock: &Clock.now/0
      )

    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(:default_rt_cb, err_fn())
    assert :open = LeakyBucketCircuitBreaker.state(:default_rt_cb)

    Clock.advance(29_999)
    assert :open = LeakyBucketCircuitBreaker.state(:default_rt_cb)

    Clock.advance(1)
    assert :half_open = LeakyBucketCircuitBreaker.state(:default_rt_cb)
  end

  test "default leak_rate_per_sec of 1.0 leaks one drop per second", %{cb: _cb} do
    # TODO
  end

  test "default failure_weight of 1.0 adds one drop per failure", %{cb: _cb} do
    {:ok, _pid} =
      LeakyBucketCircuitBreaker.start_link(
        name: :default_wt_cb,
        bucket_capacity: 5.0,
        leak_rate_per_sec: 1.0,
        reset_timeout_ms: 1_000,
        clock: &Clock.now/0
      )

    LeakyBucketCircuitBreaker.call(:default_wt_cb, err_fn())
    assert 1.0 == LeakyBucketCircuitBreaker.bucket_level(:default_wt_cb)
  end
end
```
