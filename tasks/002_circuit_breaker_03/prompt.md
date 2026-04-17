Implement the private `handle_open/2` function. It should check whether enough time has passed since the circuit was opened, based on `reset_timeout_ms` and `opened_at`, using the provided `clock/0` function.

If the timeout has not elapsed, return `{:error, :circuit_open}` without executing the function.

If the timeout has elapsed, transition the circuit to the `:half_open` state, reset `probe_count` to 0, and immediately delegate execution to `handle_half_open/2` with the updated state and the provided function.

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
    # TODO
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
    %{state |
      circuit_state: :open,
      opened_at: state.clock.(),
      failure_count: 0,
      probe_count: 0
    }
  end

  defp reset_to_closed(state) do
    %{state |
      circuit_state: :closed,
      failure_count: 0,
      opened_at: nil,
      probe_count: 0
    }
  end
end
```