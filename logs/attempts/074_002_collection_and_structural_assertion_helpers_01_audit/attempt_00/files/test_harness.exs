defmodule AssertHelpersTest do
  use ExUnit.Case, async: false
  use AssertHelpers

  describe "assert_subset/2" do
    test "passes when all elements are present" do
      assert_subset([1, 2], [1, 2, 3])
    end

    test "passes with duplicate elements in the subset" do
      assert_subset([1, 1, 2], [1, 2, 3])
    end

    test "passes for an empty subset" do
      assert_subset([], [1, 2, 3])
    end

    test "fails and lists the missing elements" do
      result =
        try do
          assert_subset([1, 4], [1, 2, 3])
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "4"
      assert result =~ "missing"
    end

    test "failure message shows both collections" do
      message =
        try do
          assert_subset([9], [1, 2, 3])
          ""
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      assert message =~ "subset"
      assert message =~ "superset"
    end
  end

  describe "assert_has_keys/2" do
    test "passes when the map has all keys" do
      assert_has_keys(%{a: 1, b: 2, c: 3}, [:a, :b])
    end

    test "accepts a single key (not wrapped in a list)" do
      assert_has_keys(%{a: 1}, :a)
    end

    test "passes for an empty key list" do
      assert_has_keys(%{a: 1}, [])
    end

    test "fails and lists missing keys" do
      result =
        try do
          assert_has_keys(%{a: 1}, [:a, :z])
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ ":z"
    end

    test "failure message shows the present keys" do
      message =
        try do
          assert_has_keys(%{a: 1, b: 2}, [:missing])
          ""
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      assert message =~ "present"
    end
  end

  describe "assert_sorted_by/2" do
    test "passes for a list sorted ascending by key" do
      people = [%{name: "A", age: 20}, %{name: "B", age: 30}, %{name: "C", age: 40}]
      assert_sorted_by(people, & &1.age)
    end

    test "passes for equal keys (non-strict ascending)" do
      assert_sorted_by([%{age: 10}, %{age: 10}], & &1.age)
    end

    test "passes for an empty list" do
      assert_sorted_by([], & &1)
    end

    test "passes for a single-element list" do
      assert_sorted_by([%{age: 5}], & &1.age)
    end

    test "fails and reports the first out-of-order pair" do
      people = [%{age: 20}, %{age: 40}, %{age: 30}]

      result =
        try do
          assert_sorted_by(people, & &1.age)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "index 1"
    end

    test "failure message includes the computed keys" do
      message =
        try do
          assert_sorted_by([%{age: 40}, %{age: 10}], & &1.age)
          ""
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      assert message =~ "key"
    end
  end

  test "has_keys failure message lists the expected keys alongside the missing ones" do
    message =
      try do
        assert_has_keys(%{a: 1, b: 2}, [:a, :zz])
        ""
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    assert message =~ "expected"
    expected_lines = for l <- String.split(message, "\n"), l =~ "expected", do: l
    assert Enum.any?(expected_lines, fn l -> l =~ ":a" and l =~ ":zz" end)
  end

  test "sorted failure message includes both offending elements verbatim" do
    a = %{name: "B", age: 40}
    b = %{name: "C", age: 30}

    message =
      try do
        assert_sorted_by([%{name: "A", age: 20}, a, b], & &1.age)
        ""
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    assert message =~ inspect(a)
    assert message =~ inspect(b)
    assert message =~ "40"
    assert message =~ "30"
  end

  test "all three assertions are exported as macros and not as plain functions" do
    assert macro_exported?(AssertHelpers, :assert_subset, 2)
    assert macro_exported?(AssertHelpers, :assert_has_keys, 2)
    assert macro_exported?(AssertHelpers, :assert_sorted_by, 2)

    refute function_exported?(AssertHelpers, :assert_subset, 2)
    refute function_exported?(AssertHelpers, :assert_has_keys, 2)
    refute function_exported?(AssertHelpers, :assert_sorted_by, 2)
  end

  test "subset accepts arbitrary enumerables on both sides" do
    assert_subset(MapSet.new([1, 2]), 1..3)
    assert_subset(Stream.map([1, 1, 2], & &1), [1, 2, 3])

    message =
      try do
        assert_subset(Stream.map([1, 9], & &1), MapSet.new([1, 2]))
        ""
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    assert message =~ "9"
    assert message =~ "subset"
    assert message =~ "superset"
  end

  test "sorted assertion accepts any enumerable, not only lists" do
    assert_sorted_by(1..3, & &1)
    assert_sorted_by(Stream.map([1, 1, 2], & &1), & &1)

    message =
      try do
        assert_sorted_by(Stream.map([3, 1], & &1), & &1)
        ""
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    assert message =~ "index 0"
  end

  test "subset failure lists only the missing elements and not the present ones" do
    message =
      try do
        assert_subset([1, 4, 5, 4], [1, 2, 3])
        ""
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    missing_lines = for l <- String.split(message, "\n"), l =~ "missing", do: l
    assert Enum.any?(missing_lines, fn l -> l =~ "4" and l =~ "5" end)
    assert Enum.all?(missing_lines, fn l -> not (l =~ "1") end)
  end
end
