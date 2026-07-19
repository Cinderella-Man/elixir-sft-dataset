# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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
      assert_within_pct(0.99, 1.0, 2)
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

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
