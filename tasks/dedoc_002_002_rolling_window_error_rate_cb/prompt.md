# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule RollingRateCircuitBreaker do
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
