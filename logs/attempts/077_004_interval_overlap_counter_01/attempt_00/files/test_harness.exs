defmodule IntervalCounterTest do
  use ExUnit.Case, async: false

  alias IntervalCounter, as: C

  defp build(intervals) do
    Enum.reduce(intervals, C.new(), fn iv, acc -> C.insert(acc, iv) end)
  end

  # ---------------------------------------------------------------
  # Empty structure
  # ---------------------------------------------------------------

  test "empty structure counts are zero" do
    tree = C.new()
    assert C.count_overlapping(tree, {1, 10}) == 0
    assert C.count_enclosing(tree, 5) == 0
    assert C.max_concurrent(tree) == 0
    assert C.size(tree) == 0
  end

  # ---------------------------------------------------------------
  # count_overlapping
  # ---------------------------------------------------------------

  test "count_overlapping counts only matching intervals" do
    tree = build([{1, 2}, {5, 8}, {10, 15}, {20, 25}])
    assert C.count_overlapping(tree, {6, 12}) == 2
    assert C.count_overlapping(tree, {26, 30}) == 0
    assert C.count_overlapping(tree, {0, 100}) == 4
  end

  test "touching counts as overlap in count_overlapping" do
    tree = build([{1, 5}, {5, 10}])
    assert C.count_overlapping(tree, {5, 5}) == 2
  end

  test "count_overlapping counts duplicates" do
    tree = build([{2, 8}, {2, 8}, {2, 8}])
    assert C.count_overlapping(tree, {1, 10}) == 3
  end

  # ---------------------------------------------------------------
  # count_enclosing (stabbing count)
  # ---------------------------------------------------------------

  test "count_enclosing returns stabbing count" do
    tree = build([{1, 10}, {3, 7}, {6, 15}, {20, 30}])
    assert C.count_enclosing(tree, 6) == 3
    assert C.count_enclosing(tree, 25) == 1
    assert C.count_enclosing(tree, 100) == 0
  end

  test "degenerate interval stabbing" do
    tree = build([{4, 4}])
    assert C.count_enclosing(tree, 4) == 1
    assert C.count_enclosing(tree, 5) == 0
  end

  # ---------------------------------------------------------------
  # max_concurrent (peak concurrency)
  # ---------------------------------------------------------------

  test "max_concurrent for a single interval" do
    tree = build([{3, 7}])
    assert C.max_concurrent(tree) == 1
  end

  test "touching intervals give peak of 2" do
    tree = build([{1, 3}, {3, 5}])
    assert C.max_concurrent(tree) == 2
  end

  test "adjacent non-touching intervals give peak of 1" do
    tree = build([{1, 2}, {3, 4}])
    assert C.max_concurrent(tree) == 1
  end

  test "max_concurrent finds the busiest point" do
    # Overlaps: at point 5 -> {1,10},{4,6},{5,8} = 3 concurrent.
    tree = build([{1, 10}, {4, 6}, {5, 8}, {12, 15}, {13, 14}])
    assert C.max_concurrent(tree) == 3
  end

  test "max_concurrent with fully nested intervals" do
    tree = build([{1, 100}, {10, 90}, {20, 80}, {30, 70}])
    assert C.max_concurrent(tree) == 4
  end

  test "max_concurrent counts duplicate intervals" do
    tree = build([{5, 5}, {5, 5}, {5, 5}])
    assert C.max_concurrent(tree) == 3
    assert C.count_enclosing(tree, 5) == 3
  end

  # ---------------------------------------------------------------
  # Persistence
  # ---------------------------------------------------------------

  test "insert is non-destructive" do
    t0 = C.new()
    t1 = C.insert(t0, {1, 5})
    t2 = C.insert(t1, {10, 20})

    assert C.size(t0) == 0
    assert C.size(t1) == 1
    assert C.size(t2) == 2
    assert C.count_overlapping(t1, {0, 100}) == 1
    assert C.count_overlapping(t2, {0, 100}) == 2
  end

  # ---------------------------------------------------------------
  # Scale
  # ---------------------------------------------------------------

  test "counts are correct at scale" do
    # 200 disjoint intervals {i*10, i*10+9}
    tree =
      Enum.reduce(0..199, C.new(), fn i, acc ->
        C.insert(acc, {i * 10, i * 10 + 9})
      end)

    assert C.size(tree) == 200
    # Disjoint intervals -> peak concurrency 1.
    assert C.max_concurrent(tree) == 1
    # Query {95,115} touches {90,99},{100,109},{110,119}
    assert C.count_overlapping(tree, {95, 115}) == 3
    assert C.count_enclosing(tree, 155) == 1
  end

  test "max_concurrent at scale with a common overlap point" do
    # 50 intervals all covering point 500.
    tree =
      Enum.reduce(1..50, C.new(), fn i, acc ->
        C.insert(acc, {500 - i, 500 + i})
      end)

    assert C.max_concurrent(tree) == 50
    assert C.count_enclosing(tree, 500) == 50
  end
end