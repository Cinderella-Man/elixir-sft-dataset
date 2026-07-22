defmodule IntervalTree do
  @moduledoc """
  A persistent, purely-functional interval tree for efficient overlapping range queries.

  The tree is an augmented AVL (self-balancing binary search tree) keyed on the interval
  `start` value. Every node additionally stores `max_finish`, the maximum `finish` value
  across its entire subtree. That augmentation, together with the BST ordering on `start`,
  lets the query functions prune whole branches instead of scanning every node.

  Complexities, with `n` stored intervals and `k` matching results:

    * `insert/2` — O(log n)
    * `overlapping/2` — O(log n + k)
    * `enclosing/2` — O(log n + k)

  The structure is a multiset: inserting the same interval twice stores it twice, and a
  matching query returns it twice. Query result ordering is unspecified; sort the result
  yourself if you need a deterministic order.

  Every value returned by `new/0` and `insert/2` is immutable — a tree a caller holds on
  to remains queryable and unchanged no matter how many further inserts derive from it.

  ## Examples

      iex> tree = IntervalTree.new()
      iex> tree = IntervalTree.insert(tree, {1, 3})
      iex> tree = IntervalTree.insert(tree, {5, 8})
      iex> IntervalTree.overlapping(tree, {3, 5}) |> Enum.sort()
      [{1, 3}, {5, 8}]
      iex> IntervalTree.enclosing(tree, 6)
      [{5, 8}]

  """

  @typedoc "An interval with inclusive integer endpoints, where `start <= finish`."
  @type interval :: {integer(), integer()}

  @typedoc "An interval tree value. Opaque; build it with `new/0` and `insert/2`."
  @opaque t :: :empty | node_t

  @typep node_t :: {:node, integer(), integer(), integer(), pos_integer(), t, t}

  # A node is {:node, start, finish, max_finish, height, left, right}.

  @doc """
  Returns a new, empty interval tree.

  ## Examples

      iex> IntervalTree.overlapping(IntervalTree.new(), {0, 10})
      []

  """
  @spec new() :: t
  def new, do: :empty

  @doc """
  Inserts `interval` into `tree` and returns the updated tree.

  Runs in O(log n). Duplicates are kept: inserting the same interval twice stores two
  copies. The input tree is never mutated.

  ## Examples

      iex> tree = IntervalTree.insert(IntervalTree.new(), {2, 4})
      iex> IntervalTree.enclosing(tree, 3)
      [{2, 4}]

  """
  @spec insert(t, interval) :: t
  def insert(tree, {start, finish}) when is_integer(start) and is_integer(finish) do
    do_insert(tree, start, finish)
  end

  @doc """
  Returns every stored interval that overlaps the query range `{start, finish}`.

  Two intervals overlap when they share at least one point, so touching endpoints count:
  `{1, 3}` overlaps `{3, 5}`. Runs in O(log n + k) where `k` is the number of matches.
  The order of the returned list is unspecified.

  ## Examples

      iex> tree = Enum.reduce([{1, 3}, {6, 9}], IntervalTree.new(), &IntervalTree.insert(&2, &1))
      iex> IntervalTree.overlapping(tree, {4, 9})
      [{6, 9}]
      iex> IntervalTree.overlapping(tree, {4, 5})
      []

  """
  @spec overlapping(t, interval) :: [interval]
  def overlapping(tree, {start, finish}) when is_integer(start) and is_integer(finish) do
    collect_overlapping(tree, start, finish, [])
  end

  @doc """
  Returns every stored interval that contains `point`, i.e. every `{s, f}` with
  `s <= point <= f`.

  Endpoints count, so a stored `{1, 5}` is returned for both `1` and `5`. Runs in
  O(log n + k). The order of the returned list is unspecified.

  ## Examples

      iex> tree = IntervalTree.insert(IntervalTree.new(), {1, 5})
      iex> IntervalTree.enclosing(tree, 5)
      [{1, 5}]
      iex> IntervalTree.enclosing(tree, 6)
      []

  """
  @spec enclosing(t, integer()) :: [interval]
  def enclosing(tree, point) when is_integer(point) do
    collect_overlapping(tree, point, point, [])
  end

  # --- Insertion -------------------------------------------------------------------

  @spec do_insert(t, integer(), integer()) :: t
  defp do_insert(:empty, start, finish) do
    {:node, start, finish, finish, 1, :empty, :empty}
  end

  defp do_insert({:node, s, f, _max, _h, left, right}, start, finish) do
    # Ties on `start` go left, which keeps duplicates in the tree (multiset semantics).
    if start <= s do
      balance(s, f, do_insert(left, start, finish), right)
    else
      balance(s, f, left, do_insert(right, start, finish))
    end
  end

  # --- Queries ---------------------------------------------------------------------

  # Collects every stored interval overlapping [qs, qf] onto `acc`.
  #
  # Pruning rules:
  #   * if the subtree's max_finish < qs, no interval in it can reach the query — skip it;
  #   * if the node's start > qf, then by BST ordering every interval in the right subtree
  #     also starts after qf and cannot overlap — skip the right subtree.
  @spec collect_overlapping(t, integer(), integer(), [interval]) :: [interval]
  defp collect_overlapping(:empty, _qs, _qf, acc), do: acc

  defp collect_overlapping({:node, s, f, max, _h, left, right}, qs, qf, acc) do
    if max < qs do
      acc
    else
      acc = collect_overlapping(left, qs, qf, acc)

      if s > qf do
        acc
      else
        acc = if f >= qs, do: [{s, f} | acc], else: acc
        collect_overlapping(right, qs, qf, acc)
      end
    end
  end

  # --- AVL machinery ---------------------------------------------------------------

  @spec height(t) :: non_neg_integer()
  defp height(:empty), do: 0
  defp height({:node, _s, _f, _max, h, _l, _r}), do: h

  @spec subtree_max(t) :: integer() | nil
  defp subtree_max(:empty), do: nil
  defp subtree_max({:node, _s, _f, max, _h, _l, _r}), do: max

  @spec make_node(integer(), integer(), t, t) :: node_t
  defp make_node(s, f, left, right) do
    max =
      [f, subtree_max(left), subtree_max(right)]
      |> Enum.reject(&is_nil/1)
      |> Enum.max()

    height = 1 + Kernel.max(height(left), height(right))
    {:node, s, f, max, height, left, right}
  end

  # Rebuilds the node rooted at {s, f} and restores the AVL invariant if it was broken
  # by a single insertion into `left` or `right`.
  @spec balance(integer(), integer(), t, t) :: node_t
  defp balance(s, f, left, right) do
    case height(left) - height(right) do
      2 ->
        {:node, ls, lf, _lmax, _lh, ll, lr} = left

        if height(ll) >= height(lr) do
          # Left-left: single right rotation.
          make_node(ls, lf, ll, make_node(s, f, lr, right))
        else
          # Left-right: double rotation.
          {:node, lrs, lrf, _m, _h, lrl, lrr} = lr
          make_node(lrs, lrf, make_node(ls, lf, ll, lrl), make_node(s, f, lrr, right))
        end

      -2 ->
        {:node, rs, rf, _rmax, _rh, rl, rr} = right

        if height(rr) >= height(rl) do
          # Right-right: single left rotation.
          make_node(rs, rf, make_node(s, f, left, rl), rr)
        else
          # Right-left: double rotation.
          {:node, rls, rlf, _m, _h, rll, rlr} = rl
          make_node(rls, rlf, make_node(s, f, left, rll), make_node(rs, rf, rlr, rr))
        end

      _balanced ->
        make_node(s, f, left, right)
    end
  end
end