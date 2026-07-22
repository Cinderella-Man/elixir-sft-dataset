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

  test "matches the needle against Exception.message/1 output, not the struct fields" do
    assert_raises_message(File.Error, "no such file or directory", fn ->
      raise File.Error, reason: :enoent, action: "read file", path: "nope.txt"
    end)
  end

  test "reports the first violating pair with both of its elements" do
    result =
      try do
        assert_monotonic([10, 7, 999, 5])
        :no_failure
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    refute result == :no_failure
    assert result =~ "index 0"
    assert result =~ ~r/element 0\s*: 10/
    assert result =~ ~r/element 1\s*: 7/
    refute result =~ "index 2"
  end

  test "failure message shows difference, allowed difference and the percentage delta" do
    result =
      try do
        assert_within_pct(120, 100, 5)
        :no_failure
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    refute result == :no_failure
    assert result =~ ~r/actual\s*: 120/
    assert result =~ ~r/expected\s*: 100/
    assert result =~ ~r/difference\s*: 20/
    assert result =~ ~r/allowed[^\n]*: 5\.0/
    assert result =~ ~r/delta\s*: 20\.0%/
  end

  test "expected zero rejects a tiny non-zero actual even with a huge percentage" do
    result =
      try do
        assert_within_pct(0.001, 0, 1_000_000)
        :no_failure
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    refute result == :no_failure
  end

  test "fails for equal adjacent values in a decreasing sequence" do
    result =
      try do
        assert_monotonic([9, 5, 5, 1], :decreasing)
        :no_failure
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    refute result == :no_failure
    assert result =~ "decreasing"
    assert result =~ "index 1"
  end

  test "uses the magnitude of a negative expected value for the tolerance" do
    assert_within_pct(-105, -100, 5)
  end
end
