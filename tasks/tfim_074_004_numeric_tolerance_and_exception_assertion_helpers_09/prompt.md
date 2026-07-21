# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule AssertHelpers do
  @moduledoc """
  Custom ExUnit assertion macros for numeric tolerance and exception semantics.

  ## Usage

      defmodule MyApp.SomeTest do
        use ExUnit.Case
        use AssertHelpers

        test "example" do
          assert_within_pct(measured, 100, 5)
          assert_monotonic(timestamps)
          assert_raises_message(ArgumentError, "invalid", fn -> parse!("x") end)
        end
      end
  """

  @doc false
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers
    end
  end

  # ---------------------------------------------------------------------------
  # assert_within_pct/3
  # ---------------------------------------------------------------------------

  @doc """
  Asserts that `actual` is within `pct` percent of `expected`:

      abs(actual - expected) <= abs(expected) * pct / 100

  When `expected == 0`, only `actual == 0` passes. On failure the message
  shows the values, the absolute difference, the allowed difference, and the
  actual percentage delta.
  """
  @spec assert_within_pct(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_within_pct(actual, expected, pct) do
    quote bind_quoted: [actual: actual, expected: expected, pct: pct] do
      allowed = abs(expected) * (pct / 100)
      diff = abs(actual - expected)

      actual_pct =
        if expected == 0 do
          if actual == 0, do: +0.0, else: :infinity
        else
          diff / abs(expected) * 100
        end

      unless diff <= allowed do
        ExUnit.Assertions.flunk("""
        assert_within_pct failed

          actual          : #{inspect(actual)}
          expected        : #{inspect(expected)}
          difference      : #{inspect(diff)}
          allowed (±#{pct}%) : #{inspect(allowed)}
          actual delta    : #{inspect(actual_pct)}%
        """)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # assert_monotonic/2
  # ---------------------------------------------------------------------------

  @doc """
  Asserts that `list` is a strictly monotonic sequence in `direction`
  (`:increasing` or `:decreasing`). Equal adjacent values are a violation.

  On failure reports the index and both elements of the first violating pair.
  """
  @spec assert_monotonic(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_monotonic(list, direction \\ :increasing) do
    quote bind_quoted: [list: list, direction: direction] do
      items = Enum.to_list(list)

      case AssertHelpers.__first_non_monotonic__(items, direction) do
        :ok ->
          :ok

        {:violation, index, a, b} ->
          ExUnit.Assertions.flunk("""
          assert_monotonic (#{direction}) failed

            sequence is not strictly #{direction}
            violation at index #{index}:
              element #{index}     : #{inspect(a)}
              element #{index + 1} : #{inspect(b)}
            full sequence: #{inspect(items)}
          """)
      end
    end
  end

  # Public so the macro-generated `quote` block can call it from any module.
  @doc false
  @spec __first_non_monotonic__([term()], :increasing | :decreasing) ::
          :ok | {:violation, non_neg_integer(), term(), term()}
  def __first_non_monotonic__(items, direction) do
    items
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.find_value(:ok, fn {[a, b], i} ->
      ok? =
        case direction do
          :increasing -> a < b
          :decreasing -> a > b
        end

      if ok?, do: false, else: {:violation, i, a, b}
    end)
  end

  # ---------------------------------------------------------------------------
  # assert_raises_message/3
  # ---------------------------------------------------------------------------

  @doc """
  Asserts that the zero-arity `fun` raises `exception` and that the raised
  exception's message contains the substring `needle`.

  On failure distinguishes three cases: nothing raised, wrong exception type,
  or right type but non-matching message.
  """
  @spec assert_raises_message(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_raises_message(exception, needle, fun) do
    quote bind_quoted: [exception: exception, needle: needle, fun: fun] do
      result =
        try do
          fun.()
          {:no_raise, nil}
        rescue
          e -> {:raised, e}
        end

      case result do
        {:no_raise, _} ->
          ExUnit.Assertions.flunk("""
          assert_raises_message failed

            expected #{inspect(exception)} to be raised
            but no exception was raised
          """)

        {:raised, e} ->
          cond do
            not is_struct(e, exception) ->
              ExUnit.Assertions.flunk("""
              assert_raises_message failed

                expected exception: #{inspect(exception)}
                actual exception  : #{inspect(e.__struct__)}
                message           : #{inspect(Exception.message(e))}
              """)

            not (Exception.message(e) =~ needle) ->
              ExUnit.Assertions.flunk("""
              assert_raises_message failed

                exception #{inspect(exception)} was raised as expected
                but its message did not contain the expected text
                expected substring: #{inspect(needle)}
                actual message    : #{inspect(Exception.message(e))}
              """)

            true ->
              :ok
          end
      end
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule AssertHelpersTest do
  use ExUnit.Case, async: false
  use AssertHelpers

  describe "assert_within_pct/3" do
    test "passes when actual is within the allowed percentage" do
      assert_within_pct(101, 100, 5)
    end

    test "passes at the exact boundary" do
      assert_within_pct(105, 100, 5)
    end

    test "passes for floats" do
      # TODO
    end

    test "passes when both actual and expected are zero" do
      assert_within_pct(0, 0, 5)
    end

    test "fails when actual is outside the tolerance" do
      result =
        try do
          assert_within_pct(120, 100, 5)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "allowed"
      assert result =~ "120"
    end

    test "fails when expected is zero but actual is not" do
      result =
        try do
          assert_within_pct(3, 0, 5)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
    end
  end

  describe "assert_monotonic/2" do
    test "passes for a strictly increasing sequence" do
      assert_monotonic([1, 2, 3, 10])
    end

    test "passes for a strictly decreasing sequence" do
      assert_monotonic([10, 5, 1, -3], :decreasing)
    end

    test "passes for a single-element list" do
      assert_monotonic([42])
    end

    test "fails for equal adjacent values (not strict)" do
      result =
        try do
          assert_monotonic([1, 2, 2, 3])
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "index 1"
    end

    test "fails when an increasing sequence dips" do
      result =
        try do
          assert_monotonic([1, 5, 4, 9])
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "increasing"
    end

    test "failure for a decreasing sequence names the decreasing direction" do
      result =
        try do
          assert_monotonic([10, 3, 7, 1], :decreasing)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "decreasing"
      assert result =~ "index 1"
    end

    test "failure for equal adjacent values under :decreasing names that direction" do
      result =
        try do
          assert_monotonic([9, 4, 4], :decreasing)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "decreasing"
      assert result =~ "index 1"
    end
  end

  describe "assert_raises_message/3" do
    test "passes when the right exception with matching message is raised" do
      assert_raises_message(ArgumentError, "bad input", fn ->
        raise ArgumentError, "bad input value"
      end)
    end

    test "fails when no exception is raised" do
      result =
        try do
          assert_raises_message(RuntimeError, "boom", fn -> :ok end)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "no exception"
    end

    test "fails when a different exception type is raised" do
      result =
        try do
          assert_raises_message(ArgumentError, "boom", fn -> raise RuntimeError, "boom" end)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "RuntimeError"
    end

    test "fails when the message does not contain the expected text" do
      result =
        try do
          assert_raises_message(ArgumentError, "expected text", fn ->
            raise ArgumentError, "something else"
          end)

          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "did not contain"
    end
  end
end
```
