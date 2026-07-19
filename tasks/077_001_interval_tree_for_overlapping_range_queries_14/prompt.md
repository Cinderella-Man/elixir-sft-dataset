# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `do_insert` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `IntervalTree` that implements an interval tree for efficient overlapping range queries.

## Public API

- `IntervalTree.new()` — returns an empty interval tree.
- `IntervalTree.insert(tree, {start, finish})` — inserts an interval into the tree and returns the updated tree. Both `start` and `finish` are integers, and `start <= finish` is guaranteed.
- `IntervalTree.overlapping(tree, {start, finish})` — returns a list of all intervals stored in the tree that overlap with the query range.
- `IntervalTree.enclosing(tree, point)` — returns a list of all intervals stored in the tree that contain the given integer point.

All four functions return plain values, not `{:ok, _}` / `{:error, _}` tuples: `new/0` and `insert/2` return a tree value, and the two query functions return a list of `{start, finish}` tuples. There is no error path — inputs are assumed to be well-formed (integer endpoints, `start <= finish`), and the module does not validate them or raise on its own.

## Data structure requirements

The tree must be a persistent, purely-functional data structure — every `insert` returns a new tree value without mutating the input. Any tree value a caller holds on to stays queryable and unchanged forever, no matter how many further inserts derive from it, so `t1 = insert(t0, iv)` leaves `t0` answering queries exactly as it did before. It is not a GenServer or process; it's a plain data structure module.

The internal representation must be a proper interval tree: an augmented, self-balancing binary search tree keyed on `start`, where each node also stores the maximum `finish` value across its subtree. `overlapping/2` and `enclosing/2` must use that augmentation (plus BST ordering on `start`) to prune whole branches instead of visiting every node — a flat list scan is not acceptable. Insert must keep the tree balanced (AVL-style rebalancing after each insertion), so with `n` stored intervals and `k` matching results the costs are:

- `insert/2` — O(log n)
- `overlapping/2` — O(log n + k)
- `enclosing/2` — O(log n + k)

Represent the empty tree as a value the module itself defines (whatever `new/0` returns); the queries must accept it directly.

## Query semantics

**Overlap.** Two intervals overlap if they share at least one point: `{s1, f1}` overlaps `{s2, f2}` exactly when `s1 <= f2` and `f1 >= s2`. Touching counts — `{1, 3}` and `{3, 5}` overlap. Boundaries are therefore inclusive on both ends: a query `{3, 3}` against a stored `{1, 3}` matches, and a query `{4, 9}` against a stored `{1, 3}` does not.

**Enclosure.** An interval `{s, f}` contains `point` exactly when `s <= point <= f`. The endpoints themselves count: for a stored `{1, 5}`, both `enclosing(tree, 1)` and `enclosing(tree, 5)` include it, while `enclosing(tree, 6)` does not.

**Degenerate intervals.** `start == finish` is a legal, single-point interval and must behave like any other: `{7, 7}` is returned by `enclosing(tree, 7)`, by `overlapping(tree, {7, 7})`, and by any query range that includes 7. A degenerate *query* range `{p, p}` is likewise legal and returns exactly the intervals that contain `p` — the same set `enclosing(tree, p)` returns.

## Edge cases and observable contract

- **Empty tree.** `overlapping(new(), _)` and `enclosing(new(), _)` both return `[]` for any query, without raising.
- **No matches.** A query on a non-empty tree that nothing matches returns `[]`, not an error.
- **Duplicates are kept.** Inserting the same interval twice stores it twice. A query that matches it returns it twice — one entry per insertion. The tree is a multiset of intervals; there is no de-duplication and no "already present" signalling.
- **Result ordering is unspecified.** Neither query function guarantees any particular order for the returned intervals. Callers who need a deterministic order must sort the result themselves. The only guarantee is set-membership (multiset, including duplicates): every matching stored interval appears exactly as many times as it was inserted, and nothing else appears.
- **Queries are pure.** Calling `overlapping/2` or `enclosing/2` never changes the tree; repeated identical calls on the same tree value return the same multiset of intervals. Insertion order may affect the internal shape of a balanced tree, but never the multiset a query returns.
- **Insert accepts intervals in any order.** Intervals may be inserted in ascending, descending, or arbitrary `start` order; the tree stays balanced and queries stay correct in every case. Intervals sharing the same `start` are all retained.

Give me the complete module in a single file. Use only the Elixir standard library, no external dependencies.

## The module with `do_insert` missing

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
  @spec overlapping(t(), interval()) :: [interval()]
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

  defp do_insert(nil, interval) do
    # TODO
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

Give me only the complete implementation of `do_insert` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
