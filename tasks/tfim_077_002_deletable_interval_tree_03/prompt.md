# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule DeletableIntervalTree do
  @moduledoc """
  A persistent, purely-functional interval tree implemented as an augmented AVL
  tree that supports removal with explicit success/failure semantics.

  Each node stores:

    * `interval`   — the `{start, finish}` tuple; nodes are ordered by the full
      tuple so that `delete/2` can locate an exact interval deterministically.
    * `max_finish` — the maximum `finish` across the subtree, used to prune
      `overlapping/2` and `enclosing/2`.
    * `height`     — the AVL height, maintained across `insert/2` and `delete/2`.

  Two intervals overlap when they share at least one point, so `{1, 3}` and
  `{3, 5}` overlap. Every `insert/2` and every successful `delete/2` returns a
  new tree value; the input tree is never mutated.
  """

  @type interval :: {integer(), integer()}
  @type t :: nil | map()

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
  """
  @spec size(t()) :: non_neg_integer()
  def size(tree), do: do_size(tree)

  # -------------------------------------------------------------------------
  # Node construction
  # -------------------------------------------------------------------------

  defp height(nil), do: 0
  defp height(%{height: h}), do: h

  defp make_node({_s, f} = interval, left, right) do
    h = 1 + max(height(left), height(right))
    mf = f |> max_with_child(left) |> max_with_child(right)
    %{interval: interval, max_finish: mf, height: h, left: left, right: right}
  end

  defp max_with_child(acc, nil), do: acc
  defp max_with_child(acc, %{max_finish: mf}), do: max(acc, mf)

  # -------------------------------------------------------------------------
  # AVL rotations / rebalance
  # -------------------------------------------------------------------------

  defp rotate_right(%{interval: xi, left: %{interval: yi, left: a, right: b}, right: c}) do
    make_node(yi, a, make_node(xi, b, c))
  end

  defp rotate_left(%{interval: xi, left: a, right: %{interval: yi, left: b, right: c}}) do
    make_node(yi, make_node(xi, a, b), c)
  end

  defp balance_factor(nil), do: 0
  defp balance_factor(%{left: l, right: r}), do: height(l) - height(r)

  defp rebalance(%{interval: xi, left: l, right: r} = node) do
    lh = height(l)
    rh = height(r)

    cond do
      lh - rh > 1 ->
        if balance_factor(l) >= 0 do
          rotate_right(node)
        else
          rotate_right(make_node(xi, rotate_left(l), r))
        end

      rh - lh > 1 ->
        if balance_factor(r) <= 0 do
          rotate_left(node)
        else
          rotate_left(make_node(xi, l, rotate_right(r)))
        end

      true ->
        node
    end
  end

  # -------------------------------------------------------------------------
  # Insertion (ordered by the full {start, finish} tuple; duplicates go left)
  # -------------------------------------------------------------------------

  defp do_insert(nil, interval), do: make_node(interval, nil, nil)

  defp do_insert(%{interval: ni} = node, interval) do
    updated =
      if interval <= ni do
        make_node(node.interval, do_insert(node.left, interval), node.right)
      else
        make_node(node.interval, node.left, do_insert(node.right, interval))
      end

    rebalance(updated)
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
        {rebalance(make_node(iv, nl, r)), found}

      target > iv ->
        {nr, found} = do_delete(r, target)
        {rebalance(make_node(iv, l, nr)), found}

      true ->
        {delete_here(make_node(iv, l, r)), true}
    end
  end

  defp delete_here(%{left: nil, right: r}), do: r
  defp delete_here(%{left: l, right: nil}), do: l

  defp delete_here(%{left: l, right: r}) do
    successor = min_interval(r)
    {nr, _found} = do_delete(r, successor)
    rebalance(make_node(successor, l, nr))
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

  # -------------------------------------------------------------------------
  # Size
  # -------------------------------------------------------------------------

  defp do_size(nil), do: 0
  defp do_size(%{left: l, right: r}), do: 1 + do_size(l) + do_size(r)
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
    # TODO
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
    tree = build([{4, 4}])
    assert [{4, 4}] = T.enclosing(tree, 4)
    assert [] = T.enclosing(tree, 5)
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
end
```
