Implement the private `rebalance/1` function for this augmented AVL interval tree.

`rebalance/1` receives a freshly reconstructed node (a map with `interval`,
`left`, and `right`, whose `max_finish` and `height` were already recomputed by
`make_node/3`) and returns an AVL-balanced node. It restores the AVL invariant
using the standard four rotation cases:

- Compute the heights of the left (`l`) and right (`r`) subtrees using `height/1`.
- If the tree is **left-heavy** (`lh - rh > 1`):
  - If the left child's `balance_factor/1` is `>= 0` (left-left case), do a single
    `rotate_right/1` on the node.
  - Otherwise (left-right case), first `rotate_left/1` the left child, rebuild the
    node around that rotated left child with `make_node(xi, rotate_left(l), r)`, and
    then `rotate_right/1` the result.
- If the tree is **right-heavy** (`rh - lh > 1`):
  - If the right child's `balance_factor/1` is `<= 0` (right-right case), do a single
    `rotate_left/1` on the node.
  - Otherwise (right-left case), first `rotate_right/1` the right child, rebuild the
    node around that rotated right child with `make_node(xi, l, rotate_right(r))`, and
    then `rotate_left/1` the result.
- Otherwise the node is already balanced; return it unchanged.

Here `xi` is the node's own `interval`. Because every rotation is expressed through
`make_node/3`, the `max_finish` augmentation and `height` stay correct automatically.

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
    # TODO
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