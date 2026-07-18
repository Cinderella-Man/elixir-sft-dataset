# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule MaxOverlapIntervalTree do
  @moduledoc """
  A persistent, purely-functional structure for **aggregate stabbing-depth**
  queries over closed integer intervals.

  Where a classic interval tree enumerates matching intervals, this module
  answers *counting* questions:

    * `depth_at/2`     — how many stored intervals cover a point.
    * `max_overlap/1`  — the maximum number of intervals covering any single
      point (the maximum stabbing number).
    * `busiest_point/1`— the leftmost point achieving that maximum.

  ## Representation

  Each closed interval `[s, f]` is modelled as a pair of coordinate deltas:

      +1 at coordinate s          (coverage begins here)
      -1 at coordinate f + 1      (coverage ends after f)

  These coordinate deltas are stored in a self-balancing **AVL tree keyed by
  coordinate**, with each coordinate's delta accumulated (so duplicate
  intervals and shared endpoints simply add up).

  Every node is augmented with two aggregates over its subtree's coordinates
  taken in ascending (in-order) sequence:

    * `sum`  — the total of all deltas in the subtree.
    * `best` — the maximum running prefix sum obtained by walking the subtree's
      coordinates in ascending order and adding each delta in turn.

  Because the running prefix sum *after* applying coordinate `c` is exactly the
  number of intervals covering the region `[c, next_coordinate)`, the root's
  `best` is the maximum stabbing number — available in `O(1)` from the root and
  maintained in `O(log n)` per insert.

  ## Complexity (n = number of distinct coordinates)

    * `insert/2`        — O(log n)
    * `depth_at/2`      — O(log n)   (prefix-sum descent)
    * `max_overlap/1`   — O(1)       (read the root aggregate)
    * `busiest_point/1` — O(n)       (in-order argmax scan)

  ## Persistence

  Every `insert/2` returns a **new** tree; the input is never mutated. This is
  plain data — not a GenServer or process.
  """

  # Sentinel standing in for "no elements" when combining `best` aggregates.
  # Any real running prefix sum is far larger than this.
  @neg_inf -1_000_000_000_000_000

  @type interval :: {integer(), integer()}

  @typep node_t :: %{
           required(:coord) => integer(),
           required(:delta) => integer(),
           required(:sum) => integer(),
           required(:best) => integer(),
           required(:height) => pos_integer(),
           required(:left) => t(),
           required(:right) => t()
         }

  @type t :: nil | node_t()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Returns an empty tree."
  @spec new() :: t()
  def new(), do: nil

  @doc """
  Inserts the closed interval `[start, finish]` and returns the updated tree.

  The original `tree` is unmodified. `start <= finish` is assumed.
  """
  @spec insert(t(), interval()) :: t()
  def insert(tree, {start, finish}) do
    tree
    |> bump(start, 1)
    |> bump(finish + 1, -1)
  end

  @doc """
  Returns the number of stored intervals whose closed range contains `point`.
  """
  @spec depth_at(t(), integer()) :: number()
  def depth_at(tree, point), do: prefix_sum(tree, point)

  @doc """
  Returns the maximum number of intervals covering any single integer point.

  Returns `0` for an empty tree.
  """
  @spec max_overlap(t()) :: non_neg_integer()
  def max_overlap(nil), do: 0
  def max_overlap(%{best: best}), do: max(0, best)

  @doc """
  Returns the smallest integer point achieving `max_overlap/1`, or `nil` when
  the tree is empty.
  """
  @spec busiest_point(t()) :: integer() | nil
  def busiest_point(nil), do: nil

  def busiest_point(tree) do
    {_run, _best, coord} =
      tree
      |> in_order([])
      |> Enum.reduce({0, @neg_inf, nil}, fn {c, d}, {run, best, coord} ->
        run2 = run + d

        if run2 > best do
          {run2, run2, c}
        else
          {run2, best, coord}
        end
      end)

    coord
  end

  # ---------------------------------------------------------------------------
  # Aggregate helpers
  # ---------------------------------------------------------------------------

  @spec sum_of(t()) :: integer()
  defp sum_of(nil), do: 0
  defp sum_of(%{sum: s}), do: s

  @spec best_of(t()) :: integer()
  defp best_of(nil), do: @neg_inf
  defp best_of(%{best: b}), do: b

  @spec height(t()) :: non_neg_integer()
  defp height(nil), do: 0
  defp height(%{height: h}), do: h

  # Build a node, recomputing `sum`, `best`, and `height` from the children.
  #
  # For the in-order sequence [left..., node, right...], the maximum running
  # prefix sum is the best of:
  #   * a prefix ending inside `left`            -> best_of(left)
  #   * the prefix ending exactly at `node`      -> sum_of(left) + delta
  #   * a prefix ending inside `right`           -> sum_of(left) + delta + best_of(right)
  @spec make_node(integer(), integer(), t(), t()) :: node_t()
  defp make_node(coord, delta, left, right) do
    lsum = sum_of(left)
    after_node = lsum + delta

    node_sum = lsum + delta + sum_of(right)
    node_best = max(best_of(left), max(after_node, after_node + best_of(right)))
    node_height = 1 + max(height(left), height(right))

    %{
      coord: coord,
      delta: delta,
      sum: node_sum,
      best: node_best,
      height: node_height,
      left: left,
      right: right
    }
  end

  # ---------------------------------------------------------------------------
  # AVL rotations (rebuild affected nodes so aggregates stay correct)
  # ---------------------------------------------------------------------------

  defp rotate_right(%{
         coord: xc,
         delta: xd,
         left: %{coord: yc, delta: yd, left: a, right: b},
         right: c
       }) do
    make_node(yc, yd, a, make_node(xc, xd, b, c))
  end

  defp rotate_left(%{
         coord: xc,
         delta: xd,
         left: a,
         right: %{coord: yc, delta: yd, left: b, right: c}
       }) do
    make_node(yc, yd, make_node(xc, xd, a, b), c)
  end

  @spec balance_factor(t()) :: integer()
  defp balance_factor(nil), do: 0
  defp balance_factor(%{left: l, right: r}), do: height(l) - height(r)

  @spec rebalance(node_t()) :: node_t()
  defp rebalance(%{coord: xc, delta: xd, left: l, right: r} = node) do
    lh = height(l)
    rh = height(r)

    cond do
      lh - rh > 1 ->
        if balance_factor(l) >= 0 do
          rotate_right(node)
        else
          rotate_right(make_node(xc, xd, rotate_left(l), r))
        end

      rh - lh > 1 ->
        if balance_factor(r) <= 0 do
          rotate_left(node)
        else
          rotate_left(make_node(xc, xd, l, rotate_right(r)))
        end

      true ->
        node
    end
  end

  # ---------------------------------------------------------------------------
  # Coordinate delta insertion
  # ---------------------------------------------------------------------------

  # Add `delta` to the accumulated value at `coord`, creating the node if absent.
  @spec bump(t(), integer(), integer()) :: node_t()
  defp bump(nil, coord, delta), do: make_node(coord, delta, nil, nil)

  defp bump(%{coord: c, delta: d, left: left, right: right}, coord, delta) do
    cond do
      coord < c ->
        rebalance(make_node(c, d, bump(left, coord, delta), right))

      coord > c ->
        rebalance(make_node(c, d, left, bump(right, coord, delta)))

      true ->
        # Same coordinate: accumulate the delta; structure/heights unchanged.
        make_node(c, d + delta, left, right)
    end
  end

  # ---------------------------------------------------------------------------
  # Prefix-sum descent: total of deltas for all coordinates <= point.
  # ---------------------------------------------------------------------------

  @spec prefix_sum(t(), integer()) :: number()
  defp prefix_sum(nil, _point), do: 0

  defp prefix_sum(%{coord: c, delta: d, left: left, right: right}, point) do
    if c <= point do
      sum_of(left) + d + prefix_sum(right, point)
    else
      prefix_sum(left, point)
    end
  end

  # ---------------------------------------------------------------------------
  # In-order flattening (ascending coordinate order) for busiest_point/1.
  # ---------------------------------------------------------------------------

  @spec in_order(t(), [{integer(), integer()}]) :: [{integer(), integer()}]
  defp in_order(nil, acc), do: acc

  defp in_order(%{coord: c, delta: d, left: left, right: right}, acc) do
    in_order(left, [{c, d} | in_order(right, acc)])
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
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

  test "tree is inert data: no registered process, no behaviour, usable from another process" do
    tree = Enum.reduce(1..50, T.new(), fn i, acc -> T.insert(acc, {i, i + 3}) end)

    refute is_pid(tree)
    refute is_reference(tree)
    refute is_port(tree)

    behaviours =
      T.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    refute GenServer in behaviours
    assert Process.whereis(MaxOverlapIntervalTree) == nil

    task =
      Task.async(fn ->
        {T.max_overlap(tree), T.busiest_point(tree), T.depth_at(tree, 10)}
      end)

    assert Task.await(task, 1_000) == {4, 4, 4}
  end

  test "abutting intervals whose deltas cancel at a shared coordinate keep depth one" do
    # [1,5] ends at coordinate 6 exactly where [6,10] begins, so that coordinate
    # carries a net delta of zero and must not erase the coverage there.
    tree =
      T.new()
      |> T.insert({1, 5})
      |> T.insert({6, 10})

    assert T.depth_at(tree, 0) == 0
    assert T.depth_at(tree, 5) == 1
    assert T.depth_at(tree, 6) == 1
    assert T.depth_at(tree, 10) == 1
    assert T.depth_at(tree, 11) == 0
    assert T.max_overlap(tree) == 1
    assert T.busiest_point(tree) == 1
  end

  test "two divergent branches grown from one tree never disturb each other" do
    base = Enum.reduce(1..8, T.new(), fn i, acc -> T.insert(acc, {i, i + 1}) end)

    assert T.max_overlap(base) == 2
    assert T.busiest_point(base) == 2

    left = Enum.reduce(1..5, base, fn _, acc -> T.insert(acc, {1, 1}) end)
    right = Enum.reduce(1..5, base, fn _, acc -> T.insert(acc, {9, 9}) end)

    assert T.depth_at(left, 1) == 6
    assert T.max_overlap(left) == 6
    assert T.busiest_point(left) == 1
    assert T.depth_at(left, 9) == 1

    assert T.depth_at(right, 9) == 6
    assert T.max_overlap(right) == 6
    assert T.busiest_point(right) == 9
    assert T.depth_at(right, 1) == 1

    # The shared ancestor is unchanged by either branch.
    assert T.max_overlap(base) == 2
    assert T.busiest_point(base) == 2
    assert T.depth_at(base, 1) == 1
    assert T.depth_at(base, 9) == 1
  end

  test "three copies of one interval stack to depth three at the leftmost busiest point" do
    tree = Enum.reduce(1..3, T.new(), fn _, acc -> T.insert(acc, {2, 8}) end)

    assert T.depth_at(tree, 1) == 0
    assert T.depth_at(tree, 2) == 3
    assert T.depth_at(tree, 8) == 3
    assert T.depth_at(tree, 9) == 0
    assert T.max_overlap(tree) == 3
    assert T.busiest_point(tree) == 2
  end

  test "repeated degenerate intervals at one coordinate stack with touching neighbours" do
    tree =
      T.new()
      |> T.insert({0, 4})
      |> T.insert({4, 4})
      |> T.insert({4, 4})
      |> T.insert({4, 9})

    assert T.depth_at(tree, 3) == 1
    assert T.depth_at(tree, 4) == 4
    assert T.depth_at(tree, 5) == 1
    assert T.depth_at(tree, 9) == 1
    assert T.depth_at(tree, 10) == 0
    assert T.max_overlap(tree) == 4
    assert T.busiest_point(tree) == 4
  end
end
```
