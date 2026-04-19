Implement the private `execute_in_closed/2` function. It handles the execution flow when the circuit breaker is in the `:closed` state.

First, execute the provided zero-arity function by passing it to `execute_and_classify/1`. This will return an `{outcome, reply}` tuple.

Next, prepend the new `outcome` to `state.outcomes`. Ensure the list does not exceed `state.config.window_size` by truncating any older outcomes.

Evaluate if the circuit needs to trip by passing the newly updated outcomes and `state.config` to `should_trip?/2`.

If it should trip, transition the process state: set `state` to `:open`, record the current time in `opened_at` using the `state.clock.()` function, empty the `outcomes` list, and reset `probes_in_flight` to 0.
If it should not trip, simply update the state with the new `outcomes` list.

In all cases, return a tuple containing the `reply` and the newly updated state.

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
    {:reply, :ok,
     %{state | state: :closed, outcomes: [], opened_at: nil, probes_in_flight: 0}}
  end

  # ---------------------------------------------------------------------------
  # Execution helpers
  # ---------------------------------------------------------------------------

  defp execute_in_closed(state, func) do
    # TODO
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
      total == 0 -> false
      total < config.min_calls_in_window -> false
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