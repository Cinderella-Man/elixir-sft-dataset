# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule LeakyBucketCircuitBreaker do
  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def call(name, func) when is_function(func, 0) do
    GenServer.call(name, {:call, func})
  end

  def state(name), do: GenServer.call(name, :get_state)

  def reset(name), do: GenServer.call(name, :reset)

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
