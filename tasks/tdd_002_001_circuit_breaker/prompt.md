# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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
    # Trip the breaker
    for _ <- 1..3, do: CircuitBreaker.call(:test_cb, error_fn())
    Clock.advance(5_000)

    # Probe succeeds
    assert {:ok, :success} = CircuitBreaker.call(:test_cb, ok_fn())
    assert CircuitBreaker.state(:test_cb) == :closed

    # Now fully operational again
    assert {:ok, :success} = CircuitBreaker.call(:test_cb, ok_fn())
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

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
