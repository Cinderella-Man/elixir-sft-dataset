# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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
      {:ok, c} = Clock.Fake.start_link(initial: 5000)
      {result, elapsed} = Clock.measure(c, fn -> 1 + 1 end)
      assert result == 2
      assert elapsed == 0
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

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
