# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule DeletableIntervalTree do
  @moduledoc """
  A persistent, purely-functional interval tree implemented as a size-balanced
  (weight-balanced) binary search tree that supports removal with explicit
  success/failure semantics.

  Each node stores:

    * `interval`   — the `{start, finish}` tuple; nodes are ordered by the full
      tuple so that `delete/2` can locate an exact interval deterministically.
    * `max_finish` — the maximum `finish` across the subtree, used to prune
      `overlapping/2` and `enclosing/2`.
    * `size`       — the number of intervals in the subtree. It answers `size/1`
      in constant time and is also the quantity the tree balances on, so the
      tree stays logarithmic after every `insert/2` and every `delete/2`.

  Two intervals overlap when they share at least one point, so `{1, 3}` and
  `{3, 5}` overlap. Every `insert/2` and every successful `delete/2` returns a
  new tree value; the input tree is never mutated, so older versions of a tree
  remain queryable.
  """

  @type interval :: {integer(), integer()}
  @type t :: nil | map()

  # Weight-balance parameters. A subtree may be at most `@delta` times heavier
  # than its sibling; `@ratio` decides between a single and a double rotation.
  @delta 3
  @ratio 2

  # -------------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------------

  @doc """
  Returns a new, empty interval tree.
  """
  @spec new() :: t()
  def new(), do: nil

  @doc """
  Inserts `interval` into `tree` and returns the updated tree.

  Both endpoints must be integers with `start <= finish`. Duplicate intervals
  are permitted; each copy is stored independently.
  """
  @spec insert(t(), interval()) :: t()
  def insert(tree, {s, f} = interval) when is_integer(s) and is_integer(f) and s <= f do
    do_insert(tree, interval)
  end

  @doc """
  Returns `true` if at least one copy of `interval` is stored in `tree`.
  """
  @spec member?(t(), interval()) :: boolean()
  def member?(tree, {_s, _f} = interval), do: do_member?(tree, interval)

  @doc """
  Removes a single occurrence of `interval` from `tree`.

  Returns `{:ok, new_tree}` when the interval was present, or
  `{:error, :not_found}` otherwise. When two identical intervals are stored,
  only one of them is removed.
  """
  @spec delete(t(), interval()) :: {:ok, t()} | {:error, :not_found}
  def delete(tree, {_s, _f} = interval) do
    case do_delete(tree, interval) do
      {new_tree, true} -> {:ok, new_tree}
      {_unchanged, false} -> {:error, :not_found}
    end
  end

  @doc """
  Returns all stored intervals that overlap the query range `{start, finish}`.

  Two intervals overlap when they share at least one point, so touching
  intervals are included.
  """
  @spec overlapping(t(), interval()) :: [interval()]
  def overlapping(nil, _query), do: []
  def overlapping(tree, {qs, qf}), do: do_overlapping(tree, qs, qf, [])

  @doc """
  Returns all stored intervals that contain the integer `point`
  (that is, `start <= point <= finish`).
  """
  @spec enclosing(t(), integer()) :: [interval()]
  def enclosing(nil, _point), do: []
  def enclosing(tree, point) when is_integer(point), do: do_enclosing(tree, point, [])

  @doc """
  Returns the number of intervals stored in `tree`.

  Runs in constant time; every node caches the size of its own subtree.
  """
  @spec size(t()) :: non_neg_integer()
  def size(nil), do: 0
  def size(%{size: n}), do: n

  # -------------------------------------------------------------------------
  # Node construction
  # -------------------------------------------------------------------------

  defp make_node({_s, f} = interval, left, right) do
    n = 1 + size(left) + size(right)
    mf = f |> max_with_child(left) |> max_with_child(right)
    %{interval: interval, max_finish: mf, size: n, left: left, right: right}
  end

  defp max_with_child(acc, nil), do: acc
  defp max_with_child(acc, %{max_finish: mf}), do: max(acc, mf)

  # -------------------------------------------------------------------------
  # Weight-balanced rebuilding / rotations
  # -------------------------------------------------------------------------

  # Rebuilds the node `interval` with children `left` and `right`, restoring the
  # weight-balance invariant. Exactly one element may have been added to or
  # removed from one of the children since they were last balanced.
  defp balance(interval, left, right) do
    ls = size(left)
    rs = size(right)

    cond do
      ls + rs <= 1 -> make_node(interval, left, right)
      rs > @delta * ls -> rotate_left(interval, left, right)
      ls > @delta * rs -> rotate_right(interval, left, right)
      true -> make_node(interval, left, right)
    end
  end

  defp rotate_left(interval, left, %{left: rl, right: rr} = right) do
    if size(rl) < @ratio * size(rr) do
      single_left(interval, left, right)
    else
      double_left(interval, left, right)
    end
  end

  defp rotate_right(interval, %{left: ll, right: lr} = left, right) do
    if size(lr) < @ratio * size(ll) do
      single_right(interval, left, right)
    else
      double_right(interval, left, right)
    end
  end

  defp single_left(i1, t1, %{interval: i2, left: t2, right: t3}) do
    make_node(i2, make_node(i1, t1, t2), t3)
  end

  defp single_right(i1, %{interval: i2, left: t1, right: t2}, t3) do
    make_node(i2, t1, make_node(i1, t2, t3))
  end

  defp double_left(i1, t1, right) do
    %{interval: i2, left: %{interval: i3, left: t2, right: t3}, right: t4} = right
    make_node(i3, make_node(i1, t1, t2), make_node(i2, t3, t4))
  end

  defp double_right(i1, left, t4) do
    %{interval: i2, left: t1, right: %{interval: i3, left: t2, right: t3}} = left
    make_node(i3, make_node(i2, t1, t2), make_node(i1, t3, t4))
  end

  # -------------------------------------------------------------------------
  # Insertion (ordered by the full {start, finish} tuple; duplicates go left)
  # -------------------------------------------------------------------------

  defp do_insert(nil, interval), do: make_node(interval, nil, nil)

  defp do_insert(%{interval: ni, left: l, right: r}, interval) do
    if interval <= ni do
      balance(ni, do_insert(l, interval), r)
    else
      balance(ni, l, do_insert(r, interval))
    end
  end

  # -------------------------------------------------------------------------
  # Membership
  # -------------------------------------------------------------------------

  defp do_member?(nil, _target), do: false

  defp do_member?(%{interval: iv, left: l, right: r}, target) do
    cond do
      target == iv -> true
      target < iv -> do_member?(l, target)
      true -> do_member?(r, target)
    end
  end

  # -------------------------------------------------------------------------
  # Deletion (returns {tree, found?})
  # -------------------------------------------------------------------------

  defp do_delete(nil, _target), do: {nil, false}

  defp do_delete(%{interval: iv, left: l, right: r}, target) do
    cond do
      target < iv ->
        {nl, found} = do_delete(l, target)
        {balance(iv, nl, r), found}

      target > iv ->
        {nr, found} = do_delete(r, target)
        {balance(iv, l, nr), found}

      true ->
        {delete_here(l, r), true}
    end
  end

  defp delete_here(nil, right), do: right
  defp delete_here(left, nil), do: left

  defp delete_here(left, right) do
    successor = min_interval(right)
    {nr, _found} = do_delete(right, successor)
    balance(successor, left, nr)
  end

  defp min_interval(%{left: nil, interval: iv}), do: iv
  defp min_interval(%{left: l}), do: min_interval(l)

  # -------------------------------------------------------------------------
  # Overlap query
  # -------------------------------------------------------------------------

  defp do_overlapping(nil, _qs, _qf, acc), do: acc
  defp do_overlapping(%{max_finish: mf}, qs, _qf, acc) when mf < qs, do: acc

  defp do_overlapping(%{interval: {s, f} = iv, left: left, right: right}, qs, qf, acc) do
    acc = if s <= qf and f >= qs, do: [iv | acc], else: acc
    acc = do_overlapping(left, qs, qf, acc)

    if s <= qf do
      do_overlapping(right, qs, qf, acc)
    else
      acc
    end
  end

  # -------------------------------------------------------------------------
  # Enclosing query
  # -------------------------------------------------------------------------

  defp do_enclosing(nil, _point, acc), do: acc
  defp do_enclosing(%{max_finish: mf}, point, acc) when mf < point, do: acc

  defp do_enclosing(%{interval: {s, f} = iv, left: left, right: right}, point, acc) do
    acc = if s <= point and point <= f, do: [iv | acc], else: acc
    acc = do_enclosing(left, point, acc)

    if s <= point do
      do_enclosing(right, point, acc)
    else
      acc
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule DeletableIntervalTreeTest do
  use ExUnit.Case, async: false

  alias DeletableIntervalTree, as: T

  defp build(intervals) do
    Enum.reduce(intervals, T.new(), fn iv, acc -> T.insert(acc, iv) end)
  end

  # ---------------------------------------------------------------
  # Empty tree
  # ---------------------------------------------------------------

  test "empty tree queries" do
    tree = T.new()
    assert [] = T.overlapping(tree, {1, 10})
    assert [] = T.enclosing(tree, 5)
    assert T.size(tree) == 0
    refute T.member?(tree, {1, 2})
  end

  test "delete on empty tree reports not_found" do
    assert {:error, :not_found} = T.delete(T.new(), {1, 2})
  end

  # ---------------------------------------------------------------
  # Basic query behaviour (parity with a plain interval tree)
  # ---------------------------------------------------------------

  test "overlapping returns only matching intervals" do
    tree = build([{1, 2}, {5, 8}, {10, 15}, {20, 25}])
    result = T.overlapping(tree, {6, 12})
    assert length(result) == 2
    assert {5, 8} in result
    assert {10, 15} in result
  end

  test "touching intervals overlap" do
    tree = build([{1, 5}, {5, 10}])
    result = T.overlapping(tree, {5, 5})
    assert length(result) == 2
    assert {1, 5} in result
    assert {5, 10} in result
  end

  test "enclosing returns all intervals covering the point" do
    tree = build([{1, 10}, {3, 7}, {6, 15}, {20, 30}])
    result = T.enclosing(tree, 6)
    assert length(result) == 3
    refute {20, 30} in result
  end

  test "degenerate interval found by exact point" do
    # TODO
  end

  # ---------------------------------------------------------------
  # member?
  # ---------------------------------------------------------------

  test "member? reflects presence" do
    tree = build([{1, 5}, {10, 20}])
    assert T.member?(tree, {1, 5})
    assert T.member?(tree, {10, 20})
    refute T.member?(tree, {1, 6})
    refute T.member?(tree, {2, 5})
  end

  # ---------------------------------------------------------------
  # delete — success and failure semantics
  # ---------------------------------------------------------------

  test "delete removes an existing interval and returns :ok tuple" do
    tree = build([{1, 5}, {10, 20}, {30, 40}])
    assert {:ok, tree2} = T.delete(tree, {10, 20})
    refute T.member?(tree2, {10, 20})
    assert T.size(tree2) == 2
    assert [] = T.overlapping(tree2, {12, 15})
  end

  test "delete of absent interval returns error and leaves tree usable" do
    tree = build([{1, 5}, {10, 20}])
    assert {:error, :not_found} = T.delete(tree, {2, 9})
    # original still intact
    assert T.member?(tree, {1, 5})
    assert T.size(tree) == 2
  end

  test "delete removes only one of two identical intervals" do
    tree = build([{2, 8}, {2, 8}])
    assert T.size(tree) == 2
    assert {:ok, tree2} = T.delete(tree, {2, 8})
    assert T.size(tree2) == 1
    assert T.member?(tree2, {2, 8})
    assert [{2, 8}] = T.overlapping(tree2, {1, 10})
    assert {:ok, tree3} = T.delete(tree2, {2, 8})
    assert T.size(tree3) == 0
    assert {:error, :not_found} = T.delete(tree3, {2, 8})
  end

  # ---------------------------------------------------------------
  # Persistence — delete does not mutate the original
  # ---------------------------------------------------------------

  test "delete is non-destructive" do
    t1 = build([{1, 5}, {10, 20}])
    {:ok, t2} = T.delete(t1, {1, 5})

    # original still has the interval
    assert T.member?(t1, {1, 5})
    assert [{1, 5}] = T.overlapping(t1, {1, 3})

    # new tree does not
    refute T.member?(t2, {1, 5})
    assert [] = T.overlapping(t2, {1, 3})
  end

  # ---------------------------------------------------------------
  # Augmentation correctness after many deletes (max_finish pruning)
  # ---------------------------------------------------------------

  test "queries stay correct after interleaved inserts and deletes at scale" do
    tree =
      Enum.reduce(0..199, T.new(), fn i, acc ->
        T.insert(acc, {i * 10, i * 10 + 9})
      end)

    assert T.size(tree) == 200

    # Delete every even-indexed interval.
    tree =
      Enum.reduce(0..199//2, tree, fn i, acc ->
        {:ok, acc2} = T.delete(acc, {i * 10, i * 10 + 9})
        acc2
      end)

    assert T.size(tree) == 100

    # {90,99} was even-indexed (i=9? -> 9 is odd, kept). Verify a kept one.
    assert T.member?(tree, {90, 99})
    # {100,109} is i=10 (even) -> deleted
    refute T.member?(tree, {100, 109})

    # Overlap query that would have touched three intervals now touches two kept ones.
    result = T.overlapping(tree, {95, 115})
    assert {90, 99} in result
    refute {100, 109} in result
    assert {110, 119} in result

    # Point query on a kept interval.
    assert [{150, 159}] = T.enclosing(tree, 155)
  end

  test "deleting the root repeatedly keeps the tree valid" do
    tree = build(for i <- 1..50, do: {i, i + 3})

    tree =
      Enum.reduce(1..50, tree, fn i, acc ->
        {:ok, acc2} = T.delete(acc, {i, i + 3})
        acc2
      end)

    assert T.size(tree) == 0
    assert [] = T.overlapping(tree, {1, 1000})
  end

  test "insert is non-destructive and every earlier tree stays queryable" do
    t1 = build([{1, 5}])
    t2 = T.insert(t1, {10, 20})
    t3 = T.insert(t2, {2, 3})

    assert T.size(t1) == 1
    refute T.member?(t1, {10, 20})
    assert [{1, 5}] = T.overlapping(t1, {0, 100})
    assert [] = T.enclosing(t1, 15)

    assert T.size(t2) == 2
    refute T.member?(t2, {2, 3})
    assert T.member?(t2, {10, 20})
    assert [{10, 20}] = T.enclosing(t2, 15)

    assert T.size(t3) == 3
    assert T.member?(t3, {2, 3})
  end

  test "both stored copies of a duplicate interval are returned by queries" do
    tree = build([{2, 8}, {2, 8}, {30, 40}])

    assert T.size(tree) == 3
    assert T.member?(tree, {2, 8})
    assert Enum.sort(T.overlapping(tree, {1, 10})) == [{2, 8}, {2, 8}]
    assert Enum.sort(T.enclosing(tree, 5)) == [{2, 8}, {2, 8}]
    assert Enum.sort(T.overlapping(tree, {0, 100})) == [{2, 8}, {2, 8}, {30, 40}]
  end

  test "pruned queries agree with brute force after scripted inserts and deletes" do
    intervals =
      for i <- 0..119 do
        s = rem(i * 37, 100)
        {s, s + rem(i * 13, 20)}
      end

    tree = build(intervals)
    to_delete = Enum.take_every(intervals, 3)

    {tree, remaining} =
      Enum.reduce(to_delete, {tree, intervals}, fn iv, {acc, rest} ->
        {:ok, acc2} = T.delete(acc, iv)
        {acc2, List.delete(rest, iv)}
      end)

    assert T.size(tree) == length(remaining)

    for qs <- 0..120//7 do
      qf = qs + 9
      expected = Enum.filter(remaining, fn {s, f} -> s <= qf and f >= qs end)
      assert Enum.sort(T.overlapping(tree, {qs, qf})) == Enum.sort(expected)
    end

    for p <- 0..120//11 do
      expected = Enum.filter(remaining, fn {s, f} -> s <= p and p <= f end)
      assert Enum.sort(T.enclosing(tree, p)) == Enum.sort(expected)
    end
  end

  test "degenerate intervals support overlap, membership and one-at-a-time deletion" do
    tree = build([{4, 4}, {4, 4}, {7, 7}])

    assert T.member?(tree, {4, 4})
    assert Enum.sort(T.overlapping(tree, {4, 4})) == [{4, 4}, {4, 4}]
    assert Enum.sort(T.overlapping(tree, {3, 8})) == [{4, 4}, {4, 4}, {7, 7}]

    assert {:ok, tree2} = T.delete(tree, {4, 4})
    assert T.size(tree2) == 2
    assert [{4, 4}] = T.enclosing(tree2, 4)

    assert {:ok, tree3} = T.delete(tree2, {4, 4})
    refute T.member?(tree3, {4, 4})
    assert {:error, :not_found} = T.delete(tree3, {4, 4})
    assert [{7, 7}] = T.overlapping(tree3, {0, 100})
  end

  test "enclosing includes both endpoints and excludes points just outside" do
    tree = build([{1, 10}, {12, 20}])

    assert [{1, 10}] = T.enclosing(tree, 1)
    assert [{1, 10}] = T.enclosing(tree, 10)
    assert [] = T.enclosing(tree, 0)
    assert [] = T.enclosing(tree, 11)
    assert [{12, 20}] = T.enclosing(tree, 12)
    assert [{12, 20}] = T.enclosing(tree, 20)
    assert [] = T.enclosing(tree, 21)
  end

  test "deleting the widest interval keeps later queries correct" do
    tree = build([{0, 1000}, {5, 6}, {10, 11}, {20, 21}, {30, 31}, {40, 41}])

    assert {:ok, tree2} = T.delete(tree, {0, 1000})
    refute T.member?(tree2, {0, 1000})
    assert [] = T.enclosing(tree2, 500)
    assert [{20, 21}] = T.overlapping(tree2, {15, 25})

    assert Enum.sort(T.overlapping(tree2, {0, 1000})) ==
             [{5, 6}, {10, 11}, {20, 21}, {30, 31}, {40, 41}]

    assert T.member?(tree, {0, 1000})
    assert [{0, 1000}] = T.enclosing(tree, 500)
  end

  # ---------------------------------------------------------------
  # size/1 is exact at every step (single-node, two-node and beyond)
  # ---------------------------------------------------------------

  test "size grows by exactly one per insert and shrinks by exactly one per delete" do
    intervals = for i <- 1..40, do: {rem(i * 7, 40), rem(i * 7, 40) + 2}

    {tree, count} =
      Enum.reduce(intervals, {T.new(), 0}, fn iv, {acc, n} ->
        acc2 = T.insert(acc, iv)
        assert T.size(acc2) == n + 1
        {acc2, n + 1}
      end)

    assert count == 40
    assert T.size(tree) == 40

    # A failed delete must not change the count.
    assert {:error, :not_found} = T.delete(tree, {1000, 1001})
    assert T.size(tree) == 40

    {empty, left_over} =
      Enum.reduce(intervals, {tree, 40}, fn iv, {acc, n} ->
        {:ok, acc2} = T.delete(acc, iv)
        assert T.size(acc2) == n - 1
        {acc2, n - 1}
      end)

    assert left_over == 0
    assert T.size(empty) == 0
    assert [] = T.overlapping(empty, {-100, 100})
  end

  test "size of a one and two element tree is exactly one and two" do
    one = build([{3, 4}])
    assert T.size(one) == 1

    two = T.insert(one, {5, 6})
    assert T.size(two) == 2

    # Duplicates each count separately.
    three = T.insert(two, {3, 4})
    assert T.size(three) == 3

    # Every earlier version keeps its own count.
    assert T.size(one) == 1
    assert T.size(two) == 2
  end

  # ---------------------------------------------------------------
  # max_finish pruning must not cut off boundary matches
  # ---------------------------------------------------------------

  test "pruning keeps an interval that ends exactly where the query starts" do
    tree = build([{1, 5}])

    assert [{1, 5}] = T.overlapping(tree, {5, 9})
    assert [{1, 5}] = T.enclosing(tree, 5)
    assert [{1, 5}] = T.overlapping(tree, {1, 1})
    assert [{1, 5}] = T.enclosing(tree, 1)

    assert [] = T.overlapping(tree, {6, 9})
    assert [] = T.enclosing(tree, 6)
    assert [] = T.overlapping(tree, {-3, 0})
    assert [] = T.enclosing(tree, 0)
  end

  test "queries include right-subtree matches that start exactly at the query end" do
    tree = build([{1, 1}, {5, 5}, {5, 9}])

    assert Enum.sort(T.overlapping(tree, {3, 5})) == [{5, 5}, {5, 9}]
    assert Enum.sort(T.enclosing(tree, 5)) == [{5, 5}, {5, 9}]
    assert Enum.sort(T.overlapping(tree, {0, 1})) == [{1, 1}]
    assert Enum.sort(T.overlapping(tree, {6, 6})) == [{5, 9}]
    assert Enum.sort(T.overlapping(tree, {0, 9})) == [{1, 1}, {5, 5}, {5, 9}]
  end

  # ---------------------------------------------------------------
  # Balance: sorted bulk work must stay logarithmic, not quadratic
  # ---------------------------------------------------------------

  @tag timeout: 30_000
  test "ascending bulk inserts, queries and deletes stay logarithmic" do
    n = 20_000

    tree = Enum.reduce(1..n, T.new(), fn i, acc -> T.insert(acc, {i, i + 1}) end)

    assert T.size(tree) == n
    assert Enum.sort(T.enclosing(tree, 10_000)) == [{9_999, 10_000}, {10_000, 10_001}]

    assert Enum.sort(T.overlapping(tree, {17_000, 17_001})) ==
             [{16_999, 17_000}, {17_000, 17_001}, {17_001, 17_002}]

    tree =
      Enum.reduce(1..n, tree, fn i, acc ->
        {:ok, acc2} = T.delete(acc, {i, i + 1})
        acc2
      end)

    assert T.size(tree) == 0
    assert [] = T.overlapping(tree, {1, n})
  end

  @tag timeout: 30_000
  test "descending bulk inserts followed by descending deletes stay logarithmic" do
    n = 20_000

    tree = Enum.reduce(n..1//-1, T.new(), fn i, acc -> T.insert(acc, {i, i}) end)
    assert T.size(tree) == n
    assert [{4_242, 4_242}] = T.enclosing(tree, 4_242)

    tree =
      Enum.reduce(n..1//-1, tree, fn i, acc ->
        {:ok, acc2} = T.delete(acc, {i, i})
        acc2
      end)

    assert T.size(tree) == 0
    assert [] = T.enclosing(tree, 4_242)
  end
end
```
