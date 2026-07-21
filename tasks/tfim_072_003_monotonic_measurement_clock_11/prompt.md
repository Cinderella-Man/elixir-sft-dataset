# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Clock do
  @moduledoc """
  Behaviour and dispatcher for monotonic clock implementations.

  Unlike a wall-clock helper, this exposes a monotonically increasing integer
  counter (like `System.monotonic_time/1`) plus `measure/2`, so tests can drive
  elapsed-time measurement deterministically.

  ## Usage

      # Production
      Clock.monotonic(Clock.Real, :millisecond)

      # Tests — advance a fake to control measured durations
      {:ok, c} = Clock.Fake.start_link([])
      {result, ms} = Clock.measure(c, fn ->
        Clock.Fake.advance(c, milliseconds: 250)
        :ok
      end)
      # => {:ok, 250}
  """

  @doc "Returns the current monotonic time as an integer in `unit`."
  @callback monotonic(unit :: System.time_unit()) :: integer()

  @doc "Dispatches `monotonic/1` to the correct implementation."
  @spec monotonic(module() | GenServer.server(), System.time_unit()) :: integer()
  def monotonic(clock, unit \\ :millisecond)

  def monotonic(clock, unit) when is_atom(clock) do
    if function_exported?(clock, :monotonic, 1) do
      clock.monotonic(unit)
    else
      Clock.Fake.monotonic(clock, unit)
    end
  end

  def monotonic(clock, unit), do: Clock.Fake.monotonic(clock, unit)

  @doc """
  Measures how much monotonic time `fun` consumes.

  Reads the clock in microseconds before and after `fun`, and returns
  `{fun_result, elapsed_milliseconds}` (integer millisecond delta).
  """
  @spec measure(module() | GenServer.server(), (-> any())) :: {any(), non_neg_integer()}
  def measure(clock, fun) when is_function(fun, 0) do
    t0 = monotonic(clock, :microsecond)
    result = fun.()
    t1 = monotonic(clock, :microsecond)
    {result, div(t1 - t0, 1000)}
  end
end

# ---------------------------------------------------------------------------

defmodule Clock.Real do
  @moduledoc "Production monotonic clock — delegates straight to the VM."

  @behaviour Clock

  @impl Clock
  @spec monotonic(System.time_unit()) :: integer()
  def monotonic(unit), do: System.monotonic_time(unit)
end

# ---------------------------------------------------------------------------

defmodule Clock.Fake do
  @moduledoc """
  A controllable, process-based monotonic clock for tests.

  The counter is held internally in microseconds and only moves when you call
  `advance/2`, so measured durations are fully deterministic.

  ## Starting

      {:ok, c} = Clock.Fake.start_link([])                 # starts at 0
      {:ok, c} = Clock.Fake.start_link(initial: 1000)      # starts at 1000 ms
  """

  use GenServer

  @default_initial_ms 0

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {initial_ms, opts} = Keyword.pop(opts, :initial, @default_initial_ms)
    {name_opt, _rest} = Keyword.pop(opts, :name)
    gen_opts = if name_opt, do: [name: name_opt], else: []
    # Store the counter in microseconds internally.
    GenServer.start_link(__MODULE__, initial_ms * 1000, gen_opts)
  end

  @doc "Returns the current monotonic value converted to `unit`."
  @spec monotonic(GenServer.server(), System.time_unit()) :: integer()
  def monotonic(server, unit \\ :millisecond), do: GenServer.call(server, {:monotonic, unit})

  @doc "Moves the counter forward by `duration` (a keyword list of time units)."
  @spec advance(GenServer.server(), keyword()) :: :ok
  def advance(server, duration) when is_list(duration),
    do: GenServer.call(server, {:advance, duration})

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(micros) when is_integer(micros), do: {:ok, micros}

  @impl GenServer
  def handle_call({:monotonic, unit}, _from, micros) do
    {:reply, convert(micros, unit), micros}
  end

  def handle_call({:advance, duration}, _from, micros) do
    {:reply, :ok, micros + duration_to_micros(duration)}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp convert(micros, :microsecond), do: micros
  defp convert(micros, :millisecond), do: div(micros, 1_000)
  defp convert(micros, :second), do: div(micros, 1_000_000)
  defp convert(micros, :nanosecond), do: micros * 1_000

  @unit_micros %{
    microsecond: 1,
    microseconds: 1,
    millisecond: 1_000,
    milliseconds: 1_000,
    second: 1_000_000,
    seconds: 1_000_000,
    minute: 60_000_000,
    minutes: 60_000_000,
    hour: 3_600_000_000,
    hours: 3_600_000_000
  }

  defp duration_to_micros(duration) do
    Enum.reduce(duration, 0, fn {unit, amount}, acc ->
      acc + amount * Map.fetch!(@unit_micros, unit)
    end)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule ClockV2Test do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Clock.Real
  # -------------------------------------------------------

  describe "Clock.Real" do
    test "monotonic/1 returns an integer" do
      assert is_integer(Clock.Real.monotonic(:millisecond))
    end

    test "monotonic time is non-decreasing" do
      a = Clock.Real.monotonic(:microsecond)
      b = Clock.Real.monotonic(:microsecond)
      assert b >= a
    end
  end

  # -------------------------------------------------------
  # Clock.Fake — counter and units
  # -------------------------------------------------------

  describe "Clock.Fake counter" do
    test "starts at zero by default" do
      {:ok, c} = Clock.Fake.start_link([])
      assert Clock.Fake.monotonic(c, :millisecond) == 0
      assert Clock.Fake.monotonic(c, :microsecond) == 0
    end

    test "honours an :initial offset in milliseconds" do
      {:ok, c} = Clock.Fake.start_link(initial: 1000)
      assert Clock.Fake.monotonic(c, :millisecond) == 1000
      assert Clock.Fake.monotonic(c, :second) == 1
      assert Clock.Fake.monotonic(c, :microsecond) == 1_000_000
      assert Clock.Fake.monotonic(c, :nanosecond) == 1_000_000_000
    end

    test "default unit is milliseconds" do
      {:ok, c} = Clock.Fake.start_link(initial: 42)
      assert Clock.Fake.monotonic(c) == Clock.Fake.monotonic(c, :millisecond)
    end

    test "advance moves the counter forward and is unit-consistent" do
      {:ok, c} = Clock.Fake.start_link([])
      Clock.Fake.advance(c, seconds: 2)
      assert Clock.Fake.monotonic(c, :second) == 2
      assert Clock.Fake.monotonic(c, :millisecond) == 2000
      assert Clock.Fake.monotonic(c, :microsecond) == 2_000_000
    end

    test "advance is cumulative and mixes units" do
      {:ok, c} = Clock.Fake.start_link([])
      Clock.Fake.advance(c, milliseconds: 250)
      Clock.Fake.advance(c, seconds: 1, milliseconds: 500)
      assert Clock.Fake.monotonic(c, :millisecond) == 1750
    end

    test "monotonic is never decreasing across advances" do
      {:ok, c} = Clock.Fake.start_link([])
      t0 = Clock.Fake.monotonic(c, :microsecond)
      Clock.Fake.advance(c, microseconds: 5)
      t1 = Clock.Fake.monotonic(c, :microsecond)
      assert t1 >= t0
    end
  end

  # -------------------------------------------------------
  # Clock.Fake.advance/2 — full documented unit vocabulary
  # -------------------------------------------------------

  describe "Clock.Fake.advance/2 unit vocabulary" do
    test "minutes and hours advance by their full-length equivalents" do
      {:ok, c} = Clock.Fake.start_link([])

      Clock.Fake.advance(c, minutes: 2)
      assert Clock.Fake.monotonic(c, :second) == 120
      assert Clock.Fake.monotonic(c, :millisecond) == 120_000

      Clock.Fake.advance(c, hours: 1)
      assert Clock.Fake.monotonic(c, :second) == 3720
      assert Clock.Fake.monotonic(c, :millisecond) == 3_720_000
      assert Clock.Fake.monotonic(c, :microsecond) == 3_720_000_000
    end

    test "singular unit keys advance identically to their plural forms" do
      {:ok, singular} = Clock.Fake.start_link([])
      {:ok, plural} = Clock.Fake.start_link([])

      Clock.Fake.advance(singular, microsecond: 7, millisecond: 3, second: 5)
      Clock.Fake.advance(singular, minute: 2, hour: 1)

      Clock.Fake.advance(plural, microseconds: 7, milliseconds: 3, seconds: 5)
      Clock.Fake.advance(plural, minutes: 2, hours: 1)

      assert Clock.Fake.monotonic(singular, :microsecond) == 3_725_003_007

      assert Clock.Fake.monotonic(singular, :microsecond) ==
               Clock.Fake.monotonic(plural, :microsecond)
    end

    test "measure reports minute-scale advances in whole milliseconds" do
      {:ok, c} = Clock.Fake.start_link([])

      {result, elapsed} =
        Clock.measure(c, fn ->
          Clock.Fake.advance(c, minute: 1, seconds: 30)
          :long
        end)

      assert result == :long
      assert elapsed == 90_000
    end
  end

  # -------------------------------------------------------
  # Clock.measure/2
  # -------------------------------------------------------

  describe "Clock.measure/2" do
    test "measures deterministic elapsed time against a fake clock" do
      {:ok, c} = Clock.Fake.start_link([])

      {result, elapsed} =
        Clock.measure(c, fn ->
          Clock.Fake.advance(c, milliseconds: 250)
          :done
        end)

      assert result == :done
      assert elapsed == 250
    end

    test "zero elapsed when the fake clock does not advance" do
      # TODO
    end

    test "works with the real clock and yields a non-negative elapsed" do
      {result, elapsed} = Clock.measure(Clock.Real, fn -> :ok end)
      assert result == :ok
      assert is_integer(elapsed)
      assert elapsed >= 0
    end
  end

  # -------------------------------------------------------
  # Clock.monotonic/2 dispatch
  # -------------------------------------------------------

  describe "Clock.monotonic/2 unified dispatch" do
    test "dispatches to Clock.Real when given the module atom" do
      assert is_integer(Clock.monotonic(Clock.Real, :second))
    end

    test "dispatches to Clock.Fake when given a pid" do
      {:ok, c} = Clock.Fake.start_link(initial: 100)
      assert Clock.monotonic(c, :millisecond) == 100
    end

    test "dispatches to Clock.Fake when given a registered name" do
      {:ok, _} = Clock.Fake.start_link(initial: 100, name: :v2_named_clock)
      assert Clock.monotonic(:v2_named_clock, :millisecond) == 100
    end

    test "default unit flows through the dispatcher" do
      {:ok, c} = Clock.Fake.start_link(initial: 7)
      assert Clock.monotonic(c) == 7
    end
  end

  # -------------------------------------------------------
  # Isolation
  # -------------------------------------------------------

  describe "isolation" do
    test "two fake clocks hold independent counters" do
      {:ok, a} = Clock.Fake.start_link(initial: 0)
      {:ok, b} = Clock.Fake.start_link(initial: 1000)

      Clock.Fake.advance(a, seconds: 1)

      assert Clock.Fake.monotonic(a, :millisecond) == 1000
      assert Clock.Fake.monotonic(b, :millisecond) == 1000
      refute Clock.Fake.monotonic(a, :second) == 2
    end
  end

  # -------------------------------------------------------
  # Injection pattern
  # -------------------------------------------------------

  describe "dependency injection pattern" do
    defmodule Timed do
      @doc "Runs `fun`, tagging it slow when measured elapsed exceeds the budget (ms)."
      def run(clock, budget_ms, fun) do
        {result, elapsed} = Clock.measure(clock, fun)
        status = if elapsed > budget_ms, do: :slow, else: :ok
        {status, result, elapsed}
      end
    end

    test "flags a slow operation deterministically" do
      {:ok, c} = Clock.Fake.start_link([])

      assert {:slow, :work, 300} =
               Timed.run(c, 100, fn ->
                 Clock.Fake.advance(c, milliseconds: 300)
                 :work
               end)
    end

    test "reports :ok when under budget" do
      {:ok, c} = Clock.Fake.start_link([])

      assert {:ok, :work, 50} =
               Timed.run(c, 100, fn ->
                 Clock.Fake.advance(c, milliseconds: 50)
                 :work
               end)
    end
  end
end
```
