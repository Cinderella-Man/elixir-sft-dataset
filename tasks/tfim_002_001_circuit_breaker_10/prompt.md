# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule CircuitBreakerTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic time control ---
  defmodule Clock do
    use Agent
    def start_link(initial), do: Agent.start_link(fn -> initial end, name: __MODULE__)
    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
  end

  # --- Helpers ---

  defp ok_fn, do: fn -> {:ok, :success} end
  defp error_fn, do: fn -> {:error, :boom} end
  defp raise_fn, do: fn -> raise "kaboom" end

  defp counting_fn(agent) do
    fn ->
      Agent.update(agent, &(&1 + 1))
      {:ok, :counted}
    end
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, _pid} =
      CircuitBreaker.start_link(
        name: :test_cb,
        failure_threshold: 3,
        reset_timeout_ms: 5_000,
        half_open_max_probes: 1,
        clock: &Clock.now/0
      )

    :ok
  end

  # -------------------------------------------------------
  # Closed state — normal operation
  # -------------------------------------------------------

  test "starts in closed state" do
    assert CircuitBreaker.state(:test_cb) == :closed
  end

  test "closed state: successful calls pass through" do
    assert {:ok, :success} = CircuitBreaker.call(:test_cb, ok_fn())
    assert CircuitBreaker.state(:test_cb) == :closed
  end

  test "closed state: failed calls return the error" do
    assert {:error, :boom} = CircuitBreaker.call(:test_cb, error_fn())
    # Still closed after one failure (threshold is 3)
    assert CircuitBreaker.state(:test_cb) == :closed
  end

  test "closed state: raising functions return error without crashing the GenServer" do
    result = CircuitBreaker.call(:test_cb, raise_fn())
    assert {:error, _exception} = result
    # GenServer still alive
    assert CircuitBreaker.state(:test_cb) == :closed
  end

  # -------------------------------------------------------
  # Transition: closed → open
  # -------------------------------------------------------

  test "transitions to open after failure_threshold failures" do
    for _ <- 1..2 do
      CircuitBreaker.call(:test_cb, error_fn())
    end

    assert CircuitBreaker.state(:test_cb) == :closed

    # Third failure trips the breaker
    CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open
  end

  test "successful calls in closed state reset the failure count" do
    # Two failures
    CircuitBreaker.call(:test_cb, error_fn())
    CircuitBreaker.call(:test_cb, error_fn())

    # A success should reset (or at least not contribute to threshold)
    CircuitBreaker.call(:test_cb, ok_fn())

    # Two more failures — should NOT trip if the success reset the count
    CircuitBreaker.call(:test_cb, error_fn())
    CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :closed

    # Third consecutive failure now trips it
    CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open
  end

  # -------------------------------------------------------
  # Open state — failing fast
  # -------------------------------------------------------

  test "open state: calls return :circuit_open without executing the function" do
    # Trip the breaker
    for _ <- 1..3, do: CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open

    # Track whether the function gets called
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    assert {:error, :circuit_open} = CircuitBreaker.call(:test_cb, counting_fn(counter))
    # function was never called
    assert Agent.get(counter, & &1) == 0
  end

  # -------------------------------------------------------
  # Transition: open → half-open (after timeout)
  # -------------------------------------------------------

  test "transitions to half-open after reset_timeout_ms" do
    # Trip the breaker
    for _ <- 1..3, do: CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open

    # Not enough time
    Clock.advance(4_999)
    CircuitBreaker.call(:test_cb, ok_fn())
    assert CircuitBreaker.state(:test_cb) == :open

    # Enough time — next call should go through as a probe
    # now at 5000ms total
    Clock.advance(1)
    result = CircuitBreaker.call(:test_cb, ok_fn())
    # The call should have been allowed through
    assert result == {:ok, :success}
  end

  # -------------------------------------------------------
  # Half-open state
  # -------------------------------------------------------

  test "half-open: successful probe closes the circuit" do
    # TODO
  end

  test "half-open: failed probe reopens the circuit" do
    # Trip the breaker
    for _ <- 1..3, do: CircuitBreaker.call(:test_cb, error_fn())
    Clock.advance(5_000)

    # Probe fails
    assert {:error, :boom} = CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open

    # Needs another full timeout before trying again
    assert {:error, :circuit_open} = CircuitBreaker.call(:test_cb, ok_fn())
  end

  test "half-open: excess calls beyond probe limit get circuit_open" do
    # Trip the breaker
    for _ <- 1..3, do: CircuitBreaker.call(:test_cb, error_fn())
    Clock.advance(5_000)

    # With half_open_max_probes = 1 and synchronous calls, the probe call
    # completes before any second call starts. A failed probe therefore
    # returns the breaker to :open and blocks the next call immediately.

    # Probe fails → back to open
    CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open

    # Immediately blocked again
    assert {:error, :circuit_open} = CircuitBreaker.call(:test_cb, ok_fn())
  end

  # -------------------------------------------------------
  # Manual reset
  # -------------------------------------------------------

  test "reset from open state returns to closed" do
    for _ <- 1..3, do: CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open

    CircuitBreaker.reset(:test_cb)
    assert CircuitBreaker.state(:test_cb) == :closed

    # Fully operational
    assert {:ok, :success} = CircuitBreaker.call(:test_cb, ok_fn())
  end

  test "reset from closed state is a no-op (stays closed, counter resets)" do
    CircuitBreaker.call(:test_cb, error_fn())
    CircuitBreaker.call(:test_cb, error_fn())

    CircuitBreaker.reset(:test_cb)
    assert CircuitBreaker.state(:test_cb) == :closed

    # The two failures before reset shouldn't count —
    # need full 3 new failures to trip
    CircuitBreaker.call(:test_cb, error_fn())
    CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :closed
  end

  # -------------------------------------------------------
  # Full lifecycle
  # -------------------------------------------------------

  test "full cycle: closed → open → half-open → closed" do
    # Closed: working fine
    assert {:ok, :success} = CircuitBreaker.call(:test_cb, ok_fn())
    assert CircuitBreaker.state(:test_cb) == :closed

    # Closed → Open: three failures
    for _ <- 1..3, do: CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open

    # Open: blocked
    assert {:error, :circuit_open} = CircuitBreaker.call(:test_cb, ok_fn())

    # Open → Half-open: wait for timeout
    Clock.advance(5_000)

    # Half-open → Closed: successful probe
    assert {:ok, :success} = CircuitBreaker.call(:test_cb, ok_fn())
    assert CircuitBreaker.state(:test_cb) == :closed

    # Back to normal
    assert {:ok, :success} = CircuitBreaker.call(:test_cb, ok_fn())
  end

  test "full cycle: closed → open → half-open → open → half-open → closed" do
    # Trip it
    for _ <- 1..3, do: CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open

    # Wait, probe, fail
    Clock.advance(5_000)
    CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open

    # Wait again, probe, succeed
    Clock.advance(5_000)
    assert {:ok, :success} = CircuitBreaker.call(:test_cb, ok_fn())
    assert CircuitBreaker.state(:test_cb) == :closed
  end

  test "closed state: raising functions count toward the failure threshold" do
    # threshold is 3; three raises must trip exactly like three {:error, _}
    CircuitBreaker.call(:test_cb, raise_fn())
    CircuitBreaker.call(:test_cb, raise_fn())
    assert CircuitBreaker.state(:test_cb) == :closed

    CircuitBreaker.call(:test_cb, raise_fn())
    assert CircuitBreaker.state(:test_cb) == :open
  end

  test "closed state: a raised RuntimeError is returned as the exception struct" do
    assert {:error, %RuntimeError{message: "kaboom"}} =
             CircuitBreaker.call(:test_cb, raise_fn())
  end

  test "closed state: the tripping call returns the function result not circuit_open" do
    CircuitBreaker.call(:test_cb, error_fn())
    CircuitBreaker.call(:test_cb, error_fn())

    # The threshold-crossing call itself must surface the func's error, not :circuit_open
    assert {:error, :boom} = CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open
  end

  test "default failure_threshold of 5 trips the breaker" do
    {:ok, _pid} =
      CircuitBreaker.start_link(name: :default_thr_cb, clock: &Clock.now/0)

    for _ <- 1..4, do: CircuitBreaker.call(:default_thr_cb, error_fn())
    assert CircuitBreaker.state(:default_thr_cb) == :closed

    CircuitBreaker.call(:default_thr_cb, error_fn())
    assert CircuitBreaker.state(:default_thr_cb) == :open
  end

  test "default reset_timeout_ms of 30_000 governs half-open transition" do
    {:ok, _pid} =
      CircuitBreaker.start_link(
        name: :default_rst_cb,
        failure_threshold: 1,
        clock: &Clock.now/0
      )

    CircuitBreaker.call(:default_rst_cb, error_fn())
    assert CircuitBreaker.state(:default_rst_cb) == :open

    # One millisecond short of the default window: still failing fast
    Clock.advance(29_999)
    assert {:error, :circuit_open} = CircuitBreaker.call(:default_rst_cb, ok_fn())

    # Exactly 30_000ms elapsed: the next call is allowed through as a probe
    Clock.advance(1)
    assert {:ok, :success} = CircuitBreaker.call(:default_rst_cb, ok_fn())
  end

  test "half-open: successful probe resets the failure count to zero" do
    for _ <- 1..3, do: CircuitBreaker.call(:test_cb, error_fn())
    Clock.advance(5_000)

    assert {:ok, :success} = CircuitBreaker.call(:test_cb, ok_fn())
    assert CircuitBreaker.state(:test_cb) == :closed

    # With the count reset, it must take a full fresh threshold (3) to trip again
    CircuitBreaker.call(:test_cb, error_fn())
    CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :closed

    CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open
  end
end
```
