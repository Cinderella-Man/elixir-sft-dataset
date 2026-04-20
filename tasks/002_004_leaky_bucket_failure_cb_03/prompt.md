Implement the private `execute_in_closed/2` function. This function handles logic when the circuit is in the `:closed` state. 

1. Start by calling `apply_leak/1` to ensure the bucket level is current. 
2. Execute the provided zero-arity function using `execute_and_classify/1`. 
3. If the result is a success (`{:ok, reply}`), return the result and the state as-is. 
4. If the result is a failure (`{:error, reply}`), increment the `bucket_level` by the `failure_weight`. 

If this new level meets or exceeds the `bucket_capacity`, transition the state to `:open`, set `opened_at` to the current time, and reset the `bucket_level` to **0.0**. Otherwise, simply update the state with the new level. In all failure cases, return the classified reply and the updated state.

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
    # TODO
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
        {reply,
         %{state | state: :open, opened_at: state.clock.(), probes_in_flight: 0}}
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