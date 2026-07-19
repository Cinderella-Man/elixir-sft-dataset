# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`overlapping/2` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `overlapping/2`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `overlapping/2` missing

```elixir
defmodule IntervalTree do
  @moduledoc """
  A persistent, purely-functional interval tree implemented as an augmented AVL tree.

  Each node in the tree stores:
    - An interval `{start, finish}` used as the BST key (ordered by `start`).
    - `max_finish` — the maximum `finish` value across all intervals in the subtree.
      This augmentation lets `overlapping/2` and `enclosing/2` prune entire
      branches without visiting them.
    - `height` — the AVL height used to keep the tree balanced on every `insert/2`.

  ## Complexity (n = number of stored intervals, k = result size)

    - `insert/2`       — O(log n)
    - `overlapping/2`  — O(log n + k)  (branch pruning via `max_finish` and BST start order)
    - `enclosing/2`    — O(log n + k)  (same pruning strategy)

  ## Overlap definition
  Two intervals are considered overlapping when they share at least one point,
  i.e. `{1, 3}` and `{3, 5}` overlap (touching at 3 counts).

  ## Persistence
  Every `insert/2` returns a **new** tree value. The original tree is never
  mutated. The module is plain data — it is not a GenServer or process.

  ## Examples

      iex> tree =
      ...>   IntervalTree.new()
      ...>   |> IntervalTree.insert({1, 5})
      ...>   |> IntervalTree.insert({3, 8})
      ...>   |> IntervalTree.insert({10, 15})
      iex> IntervalTree.overlapping(tree, {4, 6}) |> Enum.sort()
      [{1, 5}, {3, 8}]
      iex> IntervalTree.enclosing(tree, 4) |> Enum.sort()
      [{1, 5}, {3, 8}]
      iex> IntervalTree.overlapping(tree, {20, 25})
      []
  """

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type interval :: {integer(), integer()}

  @typep node_t :: %{
           required(:interval) => interval(),
           required(:max_finish) => integer(),
           required(:height) => pos_integer(),
           required(:left) => t(),
           required(:right) => t()
         }

  @type t :: nil | node_t()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Returns an empty interval tree."
  @spec new() :: t()
  def new(), do: nil

  @doc """
  Inserts `interval` into `tree` and returns the updated tree.

  The original `tree` is unmodified (persistent / purely-functional).
  """
  @spec insert(t(), interval()) :: t()
  def insert(tree, {_start, _finish} = interval), do: do_insert(tree, interval)

  @doc """
  Returns all intervals stored in `tree` that overlap with `query`.

  Two intervals overlap when they share at least one point:
  `{s1, f1}` overlaps `{s2, f2}` iff `s1 <= f2` and `f1 >= s2`.
  """
  # TODO: @spec
  def overlapping(nil, _query), do: []
  def overlapping(tree, {qs, qf}), do: do_overlapping(tree, qs, qf, [])

  @doc """
  Returns all intervals stored in `tree` that contain `point`.

  An interval `{s, f}` contains `point` iff `s <= point <= f`.
  """
  @spec enclosing(t(), integer()) :: [interval()]
  def enclosing(nil, _point), do: []
  def enclosing(tree, point), do: do_enclosing(tree, point, [])

  # ---------------------------------------------------------------------------
  # Node construction helpers
  # ---------------------------------------------------------------------------

  # Height of a tree (0 for the empty tree).
  @spec height(t()) :: non_neg_integer()
  defp height(nil), do: 0
  defp height(%{height: h}), do: h

  # Build a node, computing `height` and `max_finish` from children.
  @spec make_node(interval(), t(), t()) :: node_t()
  defp make_node({_s, f} = interval, left, right) do
    h = 1 + max(height(left), height(right))
    mf = f |> max_with_child(left) |> max_with_child(right)
    %{interval: interval, max_finish: mf, height: h, left: left, right: right}
  end

  # Fold the child's max_finish into a running maximum.
  @spec max_with_child(integer(), t()) :: integer()
  defp max_with_child(acc, nil), do: acc
  defp max_with_child(acc, %{max_finish: mf}), do: max(acc, mf)

  # ---------------------------------------------------------------------------
  # AVL rotations
  # ---------------------------------------------------------------------------
  # Each rotation rebuilds affected nodes via make_node so that `height` and
  # `max_finish` remain correct throughout the tree.

  # Left-heavy: right rotation around `x`, promoting left child `y`.
  #
  #       x                y
  #      / \              / \
  #     y   C    =>      A   x
  #    / \                  / \
  #   A   B                B   C
  #
  defp rotate_right(%{
         interval: xi,
         left: %{interval: yi, left: a, right: b},
         right: c
       }) do
    make_node(yi, a, make_node(xi, b, c))
  end

  # Right-heavy: left rotation around `x`, promoting right child `y`.
  #
  #     x                  y
  #    / \                / \
  #   A   y      =>      x   C
  #      / \            / \
  #     B   C          A   B
  #
  defp rotate_left(%{
         interval: xi,
         left: a,
         right: %{interval: yi, left: b, right: c}
       }) do
    make_node(yi, make_node(xi, a, b), c)
  end

  # ---------------------------------------------------------------------------
  # AVL rebalancing
  # ---------------------------------------------------------------------------
  # Invariant: every tree value this module hands out is a valid AVL tree, i.e.
  # `|height(left) - height(right)| <= 1` at every node.
  #
  # `insert/2` rebuilds a single root-to-leaf path and rebalances every rebuilt
  # node bottom-up. When `rebalance/1` runs on a node, both of that node's
  # children are already valid AVL subtrees, and the one that absorbed the new
  # interval grew by at most one level. A rebuilt node's balance factor is
  # therefore always within -2..2, and when it is exactly +2 or -2 the child on
  # the heavy side always leans (its own balance factor is +1 or -1, never 0:
  # a subtree whose height grew is never perfectly balanced).
  #
  # The `case` clauses below spell out exactly those reachable states, so any
  # tree that drifts outside the AVL invariant surfaces immediately as a
  # CaseClauseError instead of silently degrading query and insert costs.

  @spec rebalance(node_t()) :: node_t()
  defp rebalance(%{left: l, right: r} = node) do
    case height(l) - height(r) do
      2 -> fix_left_heavy(node)
      -2 -> fix_right_heavy(node)
      d when abs(d) <= 1 -> node
    end
  end

  # Left subtree is two levels taller: single right rotation when the left child
  # leans left (Left-Left), double rotation when it leans right (Left-Right).
  @spec fix_left_heavy(node_t()) :: node_t()
  defp fix_left_heavy(%{interval: xi, left: %{left: ll, right: lr} = l, right: r} = node) do
    case height(ll) - height(lr) do
      1 -> rotate_right(node)
      -1 -> rotate_right(make_node(xi, rotate_left(l), r))
    end
  end

  # Right subtree is two levels taller: single left rotation when the right child
  # leans right (Right-Right), double rotation when it leans left (Right-Left).
  @spec fix_right_heavy(node_t()) :: node_t()
  defp fix_right_heavy(%{interval: xi, left: l, right: %{left: rl, right: rr} = r} = node) do
    case height(rl) - height(rr) do
      -1 -> rotate_left(node)
      1 -> rotate_left(make_node(xi, l, rotate_right(r)))
    end
  end

  # ---------------------------------------------------------------------------
  # Insertion
  # ---------------------------------------------------------------------------

  # Insert into an empty tree — create a leaf node.
  @spec do_insert(t(), interval()) :: node_t()
  defp do_insert(nil, interval), do: make_node(interval, nil, nil)

  # Insert into an existing node: descend by start value, rebuild upward,
  # then rebalance.  Duplicates are stored (multiple identical intervals allowed).
  defp do_insert(%{interval: {ns, _nf}} = node, {s, _f} = interval) do
    updated =
      if s <= ns do
        make_node(node.interval, do_insert(node.left, interval), node.right)
      else
        make_node(node.interval, node.left, do_insert(node.right, interval))
      end

    rebalance(updated)
  end

  # ---------------------------------------------------------------------------
  # Overlap query
  # ---------------------------------------------------------------------------
  # Two intervals {s1,f1} and {s2,f2} overlap iff s1 <= f2 AND f1 >= s2.
  #
  # Pruning rules exploiting BST order and the max_finish augmentation:
  #   1. If subtree's max_finish < qs  →  no interval in this subtree reaches
  #      far enough right to touch the query.  Skip the entire subtree.
  #   2. If current node's start > qf  →  this node and every node in the
  #      right subtree starts after the query ends.  Skip right subtree.
  #      (We must still recurse into the left subtree.)

  @spec do_overlapping(t(), integer(), integer(), [interval()]) :: [interval()]
  defp do_overlapping(nil, _qs, _qf, acc), do: acc

  # Prune rule 1: entire subtree finishes before query starts.
  defp do_overlapping(%{max_finish: mf}, qs, _qf, acc) when mf < qs, do: acc

  defp do_overlapping(%{interval: {s, f} = iv, left: left, right: right}, qs, qf, acc) do
    # Check current node
    acc = if s <= qf and f >= qs, do: [iv | acc], else: acc

    # Always recurse left (already guarded by max_finish above).
    acc = do_overlapping(left, qs, qf, acc)

    # Prune rule 2: if current start > qf, the right subtree cannot overlap.
    if s <= qf do
      do_overlapping(right, qs, qf, acc)
    else
      acc
    end
  end

  # ---------------------------------------------------------------------------
  # Enclosing query
  # ---------------------------------------------------------------------------
  # {s, f} encloses `point` iff s <= point <= f.
  #
  # Pruning rules:
  #   1. If subtree's max_finish < point  →  no interval in this subtree
  #      extends far enough to contain point.  Skip.
  #   2. If current node's start > point  →  this node and every node in the
  #      right subtree start after the point.  Skip right subtree.

  @spec do_enclosing(t(), integer(), [interval()]) :: [interval()]
  defp do_enclosing(nil, _point, acc), do: acc

  # Prune rule 1: entire subtree finishes before the point.
  defp do_enclosing(%{max_finish: mf}, point, acc) when mf < point, do: acc

  defp do_enclosing(%{interval: {s, f} = iv, left: left, right: right}, point, acc) do
    # Check current node
    acc = if s <= point and point <= f, do: [iv | acc], else: acc

    # Always recurse left (guarded by max_finish above).
    acc = do_enclosing(left, point, acc)

    # Prune rule 2: right subtree starts are all > s; skip if s > point.
    if s <= point do
      do_enclosing(right, point, acc)
    else
      acc
    end
  end
end
```

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
