# Fill in the middle: `delete_here/1`

You are completing an implementation of `DeletableIntervalTree`, a persistent,
purely-functional interval tree built as an augmented AVL tree. Every function is
already written **except** the private helper `delete_here/1`, whose body has been
replaced with `# TODO`. Implement it.

## What `delete_here/1` must do

`delete_here/1` removes the node that sits at the root of the subtree it is given —
this is the node whose `interval` has already been matched by `do_delete/2` — and
returns a valid, balanced subtree that no longer contains that node. It does **not**
receive or care about the target interval; by the time it is called, the caller has
already navigated to the node to delete and rebuilt it via `make_node/3`, so the node
passed in is exactly the one being removed.

Handle the three standard BST-deletion cases, matching on the node's children:

1. **No left child** (`left: nil`): the node has at most a right child, so the
   replacement subtree is simply its right child `r`. Return `r`.
2. **No right child** (`right: nil`): symmetrically, return the left child `l`.
3. **Two children** (both `left` and `right` present): replace this node with its
   in-order successor — the smallest interval in the right subtree. Obtain that
   interval with `min_interval/1` on the right child, delete that same interval from
   the right subtree with `do_delete/2` (discarding the returned `found?` flag), and
   build a new node (`make_node/3`) whose interval is the successor, whose left child
   is the original `l`, and whose right child is the pruned right subtree. Finally,
   `rebalance/1` the result so the AVL height and `max_finish` augmentation stay
   correct.

Return the resulting subtree node (or `nil`/child) directly — `delete_here/1` returns
a tree, not a `{tree, found?}` tuple; the surrounding `do_delete/2` clause supplies the
`true` flag.

## Module (complete except for `delete_here/1`)

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

  defp delete_here(node) do
    # TODO
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