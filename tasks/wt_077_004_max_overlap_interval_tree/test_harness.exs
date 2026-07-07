defmodule MaxOverlapIntervalTreeTest do
  use ExUnit.Case, async: false

  alias MaxOverlapIntervalTree, as: T

  # -------------------------------------------------------
  # Empty tree
  # -------------------------------------------------------

  test "empty tree has zero max overlap" do
    assert T.max_overlap(T.new()) == 0
  end

  test "empty tree has nil busiest point" do
    assert T.busiest_point(T.new()) == nil
  end

  test "depth_at on empty tree is zero" do
    assert T.depth_at(T.new(), 42) == 0
  end

  # -------------------------------------------------------
  # Single interval
  # -------------------------------------------------------

  test "single interval covers its interior point" do
    tree = T.new() |> T.insert({3, 7})
    assert T.depth_at(tree, 5) == 1
  end

  test "single interval covers its endpoints" do
    tree = T.new() |> T.insert({3, 7})
    assert T.depth_at(tree, 3) == 1
    assert T.depth_at(tree, 7) == 1
  end

  test "single interval does not cover points outside it" do
    tree = T.new() |> T.insert({3, 7})
    assert T.depth_at(tree, 2) == 0
    assert T.depth_at(tree, 8) == 0
  end

  test "single interval has max overlap of one at its start" do
    tree = T.new() |> T.insert({3, 7})
    assert T.max_overlap(tree) == 1
    assert T.busiest_point(tree) == 3
  end

  # -------------------------------------------------------
  # Touching intervals count as overlapping at the touch point
  # -------------------------------------------------------

  test "touching intervals overlap at the shared endpoint" do
    tree =
      T.new()
      |> T.insert({1, 5})
      |> T.insert({5, 10})

    assert T.depth_at(tree, 5) == 2
    assert T.max_overlap(tree) == 2
    assert T.busiest_point(tree) == 5
  end

  test "point just past a touch has depth one" do
    tree =
      T.new()
      |> T.insert({1, 5})
      |> T.insert({5, 10})

    assert T.depth_at(tree, 4) == 1
    assert T.depth_at(tree, 6) == 1
  end

  # -------------------------------------------------------
  # Nested / stacked intervals
  # -------------------------------------------------------

  test "nested intervals accumulate depth" do
    tree =
      T.new()
      |> T.insert({1, 10})
      |> T.insert({2, 6})
      |> T.insert({3, 4})

    assert T.depth_at(tree, 1) == 1
    assert T.depth_at(tree, 2) == 2
    assert T.depth_at(tree, 3) == 3
    assert T.depth_at(tree, 4) == 3
    assert T.depth_at(tree, 5) == 2
    assert T.depth_at(tree, 7) == 1
    assert T.depth_at(tree, 11) == 0
  end

  test "max overlap and busiest point of nested intervals" do
    tree =
      T.new()
      |> T.insert({1, 10})
      |> T.insert({2, 6})
      |> T.insert({3, 4})

    assert T.max_overlap(tree) == 3
    assert T.busiest_point(tree) == 3
  end

  test "busiest point is the leftmost of several maxima" do
    # Two disjoint clusters each stack to depth 2.
    tree =
      T.new()
      |> T.insert({1, 3})
      |> T.insert({2, 4})
      |> T.insert({10, 12})
      |> T.insert({11, 13})

    assert T.max_overlap(tree) == 2
    assert T.busiest_point(tree) == 2
  end

  # -------------------------------------------------------
  # Degenerate (single-point) intervals
  # -------------------------------------------------------

  test "degenerate interval covers exactly its point" do
    tree = T.new() |> T.insert({4, 4})
    assert T.depth_at(tree, 4) == 1
    assert T.depth_at(tree, 3) == 0
    assert T.depth_at(tree, 5) == 0
    assert T.max_overlap(tree) == 1
    assert T.busiest_point(tree) == 4
  end

  test "degenerate interval stacks with an enclosing interval" do
    tree =
      T.new()
      |> T.insert({0, 10})
      |> T.insert({5, 5})

    assert T.depth_at(tree, 5) == 2
    assert T.max_overlap(tree) == 2
    assert T.busiest_point(tree) == 5
  end

  # -------------------------------------------------------
  # Duplicates counted with multiplicity
  # -------------------------------------------------------

  test "inserting the same interval twice doubles the depth" do
    tree =
      T.new()
      |> T.insert({2, 8})
      |> T.insert({2, 8})

    assert T.depth_at(tree, 5) == 2
    assert T.max_overlap(tree) == 2
  end

  # -------------------------------------------------------
  # Persistence — insert returns a new tree, original untouched
  # -------------------------------------------------------

  test "insert is non-destructive" do
    t0 = T.new()
    t1 = T.insert(t0, {1, 5})
    t2 = T.insert(t1, {1, 5})

    assert T.max_overlap(t0) == 0
    assert T.depth_at(t0, 3) == 0

    assert T.max_overlap(t1) == 1
    assert T.depth_at(t1, 3) == 1

    assert T.max_overlap(t2) == 2
    assert T.depth_at(t2, 3) == 2
  end

  # -------------------------------------------------------
  # Negative coordinates
  # -------------------------------------------------------

  test "handles negative coordinates" do
    tree =
      T.new()
      |> T.insert({-10, -5})
      |> T.insert({-7, -1})

    assert T.depth_at(tree, -7) == 2
    assert T.depth_at(tree, -6) == 2
    assert T.depth_at(tree, -5) == 2
    assert T.depth_at(tree, -4) == 1
    assert T.max_overlap(tree) == 2
    assert T.busiest_point(tree) == -7
  end

  # -------------------------------------------------------
  # Scale — correctness with many intervals
  # -------------------------------------------------------

  test "correct aggregates with many overlapping intervals" do
    # Interval i is [i, i+5]; a point p is covered by every i in [p-5, p].
    tree =
      Enum.reduce(0..199, T.new(), fn i, acc ->
        T.insert(acc, {i, i + 5})
      end)

    # Deep in the middle, six windows overlap.
    assert T.depth_at(tree, 100) == 6
    assert T.max_overlap(tree) == 6

    # The busiest point achieves the reported maximum overlap.
    bp = T.busiest_point(tree)
    assert T.depth_at(tree, bp) == 6
  end

  test "max overlap survives a randomized-order insertion" do
    intervals = [
      {5, 9},
      {1, 3},
      {2, 8},
      {7, 7},
      {0, 10},
      {3, 4},
      {8, 12},
      {2, 2}
    ]

    tree = Enum.reduce(intervals, T.new(), &T.insert(&2, &1))

    # Brute-force reference over a bounded coordinate window.
    reference =
      for p <- -2..15 do
        Enum.count(intervals, fn {s, f} -> s <= p and p <= f end)
      end

    expected_max = Enum.max(reference)

    assert T.max_overlap(tree) == expected_max
    assert T.depth_at(tree, T.busiest_point(tree)) == expected_max
  end
end
