# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `member?` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `DeletableIntervalTree` that implements a persistent, purely-functional interval tree supporting **removal** of intervals with explicit success/failure semantics.

I need these functions in the public API:
- `DeletableIntervalTree.new()` which returns an empty interval tree.
- `DeletableIntervalTree.insert(tree, {start, finish})` which inserts an interval and returns the updated tree. Both `start` and `finish` are integers and `start <= finish` is guaranteed. Duplicate intervals are allowed (inserting `{2, 8}` twice stores two copies).
- `DeletableIntervalTree.delete(tree, {start, finish})` which removes **one** occurrence of the given interval. It returns `{:ok, new_tree}` if the interval was present, or `{:error, :not_found}` if it was not. When two identical intervals are stored, a single `delete` removes only one of them.
- `DeletableIntervalTree.member?(tree, {start, finish})` which returns `true` if at least one copy of the interval is stored, `false` otherwise.
- `DeletableIntervalTree.overlapping(tree, {start, finish})` which returns a list of all stored intervals that overlap the query range. Two intervals overlap if they share at least one point, so `{1, 3}` and `{3, 5}` overlap (touching counts).
- `DeletableIntervalTree.enclosing(tree, point)` which returns a list of all stored intervals that contain the integer `point` (`s <= point <= f`).
- `DeletableIntervalTree.size(tree)` which returns the number of stored intervals.

The tree must be a persistent purely-functional data structure — every `insert` and every successful `delete` returns a new tree value without mutating the input, and the original tree must remain queryable. It should not be a GenServer or process; it's a plain data structure module.

The internal representation must be a proper self-balancing interval tree (an augmented balanced BST where each node stores the maximum `finish` value in its subtree) so that `overlapping` and `enclosing` prune branches efficiently, and so that `insert`/`delete` stay O(log n) with the tree kept balanced after every removal. The `max_finish` augmentation must remain correct after deletions and rebalancing.

Support degenerate intervals where `start == finish`. An empty tree must return `[]` for any query and `0` for `size`.

Give me the complete module in a single file. Use only the Elixir standard library, no external dependencies.

## The module with `member?` missing

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

  def member?(tree, {_s, _f} = interval) do
    # TODO
  end

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

Give me only the complete implementation of `member?` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
