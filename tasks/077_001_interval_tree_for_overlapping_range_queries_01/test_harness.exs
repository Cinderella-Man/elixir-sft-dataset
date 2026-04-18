defmodule IntervalTreeTest do
  use ExUnit.Case, async: true

  # -------------------------------------------------------
  # Empty tree
  # -------------------------------------------------------

  test "overlapping on empty tree returns empty list" do
    tree = IntervalTree.new()
    assert [] = IntervalTree.overlapping(tree, {1, 10})
  end

  test "enclosing on empty tree returns empty list" do
    tree = IntervalTree.new()
    assert [] = IntervalTree.enclosing(tree, 5)
  end

  # -------------------------------------------------------
  # Single interval
  # -------------------------------------------------------

  test "single interval is found by overlapping query that contains it" do
    tree = IntervalTree.new() |> IntervalTree.insert({3, 7})
    assert [{3, 7}] = IntervalTree.overlapping(tree, {1, 10})
  end

  test "single interval does not match a non-overlapping query" do
    tree = IntervalTree.new() |> IntervalTree.insert({3, 7})
    assert [] = IntervalTree.overlapping(tree, {10, 20})
  end

  test "enclosing finds interval containing the point" do
    tree = IntervalTree.new() |> IntervalTree.insert({3, 7})
    assert [{3, 7}] = IntervalTree.enclosing(tree, 5)
  end

  test "enclosing misses interval that does not contain the point" do
    tree = IntervalTree.new() |> IntervalTree.insert({3, 7})
    assert [] = IntervalTree.enclosing(tree, 8)
  end

  # -------------------------------------------------------
  # Touching intervals (end of one == start of another)
  # -------------------------------------------------------

  test "touching intervals are considered overlapping" do
    tree =
      IntervalTree.new()
      |> IntervalTree.insert({1, 5})
      |> IntervalTree.insert({5, 10})

    result = IntervalTree.overlapping(tree, {5, 5})
    assert length(result) == 2
    assert {1, 5} in result
    assert {5, 10} in result
  end

  test "query touching the end of an interval still matches" do
    tree = IntervalTree.new() |> IntervalTree.insert({1, 5})
    assert [{1, 5}] = IntervalTree.overlapping(tree, {5, 8})
  end

  test "query touching the start of an interval still matches" do
    tree = IntervalTree.new() |> IntervalTree.insert({5, 10})
    assert [{5, 10}] = IntervalTree.overlapping(tree, {2, 5})
  end

  # -------------------------------------------------------
  # Degenerate (point) intervals — start == end
  # -------------------------------------------------------

  test "degenerate interval is found when query covers its point" do
    tree = IntervalTree.new() |> IntervalTree.insert({4, 4})
    assert [{4, 4}] = IntervalTree.overlapping(tree, {1, 10})
  end

  test "degenerate interval is found by enclosing at its exact point" do
    tree = IntervalTree.new() |> IntervalTree.insert({4, 4})
    assert [{4, 4}] = IntervalTree.enclosing(tree, 4)
  end

  test "degenerate interval is missed when query does not cover its point" do
    tree = IntervalTree.new() |> IntervalTree.insert({4, 4})
    assert [] = IntervalTree.overlapping(tree, {5, 10})
  end

  test "degenerate query range matches intervals that touch that point" do
    tree =
      IntervalTree.new()
      |> IntervalTree.insert({1, 3})
      |> IntervalTree.insert({3, 6})
      |> IntervalTree.insert({4, 8})

    result = IntervalTree.overlapping(tree, {3, 3})
    assert length(result) == 2
    assert {1, 3} in result
    assert {3, 6} in result
  end

  # -------------------------------------------------------
  # Multiple intervals — correct subset returned
  # -------------------------------------------------------

  test "only overlapping intervals are returned, not all" do
    tree =
      IntervalTree.new()
      |> IntervalTree.insert({1, 2})
      |> IntervalTree.insert({5, 8})
      |> IntervalTree.insert({10, 15})
      |> IntervalTree.insert({20, 25})

    result = IntervalTree.overlapping(tree, {6, 12})
    assert length(result) == 2
    assert {5, 8} in result
    assert {10, 15} in result
  end

  test "enclosing returns all intervals that contain the point" do
    tree =
      IntervalTree.new()
      |> IntervalTree.insert({1, 10})
      |> IntervalTree.insert({3, 7})
      |> IntervalTree.insert({6, 15})
      |> IntervalTree.insert({20, 30})

    result = IntervalTree.enclosing(tree, 6)
    assert length(result) == 3
    assert {1, 10} in result
    assert {3, 7} in result
    assert {6, 15} in result
    refute {20, 30} in result
  end

  # -------------------------------------------------------
  # Persistence — insert returns new tree, original unchanged
  # -------------------------------------------------------

  test "insert is non-destructive — original tree is unchanged" do
    t0 = IntervalTree.new()
    t1 = IntervalTree.insert(t0, {1, 5})
    t2 = IntervalTree.insert(t1, {10, 20})

    assert [] = IntervalTree.overlapping(t0, {1, 100})
    assert [{1, 5}] = IntervalTree.overlapping(t1, {1, 100})

    result = IntervalTree.overlapping(t2, {1, 100})
    assert length(result) == 2
    assert {1, 5} in result
    assert {10, 20} in result
  end

  # -------------------------------------------------------
  # Duplicate intervals
  # -------------------------------------------------------

  test "inserting the same interval twice returns it twice" do
    tree =
      IntervalTree.new()
      |> IntervalTree.insert({2, 8})
      |> IntervalTree.insert({2, 8})

    result = IntervalTree.overlapping(tree, {1, 10})
    assert length(result) == 2
  end

  # -------------------------------------------------------
  # Large insertion — correctness at scale
  # -------------------------------------------------------

  test "correct results with many intervals inserted" do
    # Insert 200 non-overlapping intervals: {0,9}, {10,19}, ..., {1990,1999}
    tree =
      Enum.reduce(0..199, IntervalTree.new(), fn i, acc ->
        IntervalTree.insert(acc, {i * 10, i * 10 + 9})
      end)

    # Query that touches exactly three intervals
    result = IntervalTree.overlapping(tree, {95, 115})
    assert length(result) == 3
    assert {90, 99} in result
    assert {100, 109} in result
    assert {110, 119} in result

    # Point query
    result2 = IntervalTree.enclosing(tree, 155)
    assert [{150, 159}] = result2
  end
end
