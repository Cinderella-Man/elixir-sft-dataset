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

  # -------------------------------------------------------
  # Balance — the prompt requires a *self-balancing* BST with
  # O(log n) insert / depth_at, not a flat scan or a chain.
  # Sorted insertion is the worst case: an unbalanced BST
  # degenerates into a linked list and turns quadratic.
  # -------------------------------------------------------

  test "sorted insertion of many intervals stays fast (tree is balanced)" do
    n = 20_000

    {micros, tree} =
      :timer.tc(fn ->
        Enum.reduce(1..n, T.new(), fn i, acc -> T.insert(acc, {i, i + 2}) end)
      end)

    # Interval i is [i, i+2]; point p is covered by i in [p-2, p], so the
    # stabbing number peaks at 3, first reached at point 3.
    assert T.max_overlap(tree) == 3
    assert T.busiest_point(tree) == 3
    assert T.depth_at(tree, 10_000) == 3
    assert T.depth_at(tree, n + 3) == 0

    # A balanced tree does this in well under a second; a degenerate chain
    # needs ~n^2/2 node rebuilds and blows far past this budget.
    assert div(micros, 1000) < 5_000
  end

  test "descending insertion of many intervals stays fast (tree is balanced)" do
    n = 20_000

    {micros, tree} =
      :timer.tc(fn ->
        Enum.reduce(n..1//-1, T.new(), fn i, acc -> T.insert(acc, {i, i + 2}) end)
      end)

    assert T.max_overlap(tree) == 3
    assert T.busiest_point(tree) == 3
    assert T.depth_at(tree, 12_345) == 3
    assert div(micros, 1000) < 5_000
  end

  # -------------------------------------------------------
  # Rotations must preserve the aggregates and the old versions
  # -------------------------------------------------------

  test "aggregates stay correct through every rotation case" do
    # Each insertion order drives one of the four AVL fix-ups
    # (right-right, left-left, right-left, left-right).
    orders = [
      [{1, 1}, {2, 2}, {3, 3}],
      [{3, 3}, {2, 2}, {1, 1}],
      [{1, 1}, {3, 3}, {2, 2}],
      [{3, 3}, {1, 1}, {2, 2}]
    ]

    for order <- orders do
      tree = Enum.reduce(order, T.new(), &T.insert(&2, &1))

      assert T.depth_at(tree, 1) == 1
      assert T.depth_at(tree, 2) == 1
      assert T.depth_at(tree, 3) == 1
      assert T.depth_at(tree, 0) == 0
      assert T.depth_at(tree, 4) == 0
      assert T.max_overlap(tree) == 1
      assert T.busiest_point(tree) == 1
    end
  end

  test "rebalancing never disturbs earlier persistent versions" do
    # Version k holds the nested intervals [1,1000]..[k,1000], so its depth at
    # point k is exactly k and the leftmost maximum sits at k.
    versions = Enum.scan(1..64, T.new(), fn i, acc -> T.insert(acc, {i, 1000}) end)

    for {tree, k} <- Enum.with_index(versions, 1) do
      assert T.max_overlap(tree) == k
      assert T.busiest_point(tree) == k
      assert T.depth_at(tree, k) == k
      assert T.depth_at(tree, 1000) == k
      assert T.depth_at(tree, 1001) == 0
    end
  end

  test "random interval sets match a brute-force reference in shuffled orders" do
    :rand.seed(:exsss, {7, 11, 13})

    for _round <- 1..30 do
      intervals =
        for _ <- 1..25 do
          s = :rand.uniform(21) - 11
          {s, s + :rand.uniform(6) - 1}
        end

      tree =
        intervals
        |> Enum.shuffle()
        |> Enum.reduce(T.new(), &T.insert(&2, &1))

      {expected_max, expected_bp} = brute_stats(intervals)

      assert T.max_overlap(tree) == expected_max
      assert T.busiest_point(tree) == expected_bp

      for p <- -13..20 do
        assert T.depth_at(tree, p) == brute_depth(intervals, p)
      end
    end
  end

  # -------------------------------------------------------
  # Brute-force reference helpers
  # -------------------------------------------------------

  defp brute_depth(intervals, point) do
    Enum.count(intervals, fn {s, f} -> s <= point and point <= f end)
  end

  # Coverage only ever rises at an interval start, so the leftmost maximising
  # point is the smallest start achieving the maximum depth.
  defp brute_stats([]), do: {0, nil}

  defp brute_stats(intervals) do
    depths =
      intervals
      |> Enum.map(fn {s, _f} -> {s, brute_depth(intervals, s)} end)
      |> Enum.uniq()

    max_depth = depths |> Enum.map(fn {_s, d} -> d end) |> Enum.max()

    best_point =
      depths
      |> Enum.filter(fn {_s, d} -> d == max_depth end)
      |> Enum.map(fn {s, _d} -> s end)
      |> Enum.min()

    {max_depth, best_point}
  end
end
