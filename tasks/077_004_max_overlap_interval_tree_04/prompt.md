# Fill in the middle: `prefix_sum/2`

The module `MaxOverlapIntervalTree` is a persistent, purely-functional interval
tree that answers **aggregate stabbing-depth** queries over closed integer
intervals. Each closed interval `[s, f]` is modelled as two coordinate deltas —
`+1` at coordinate `s` and `-1` at coordinate `f + 1` — accumulated into a
self-balancing AVL tree keyed by coordinate. Every node caches the subtree's
`sum` (total of all deltas) and `best` (maximum running prefix sum in ascending
coordinate order).

Your job is to implement the private `prefix_sum/2` helper. It powers the public
`depth_at/2` query, which reports how many stored intervals contain a given
point.

Implement the private `prefix_sum(tree, point)` function. It must return the
integer total of all coordinate deltas whose coordinate is **less than or equal
to** `point` — i.e. the running coverage at `point`. Do this as an `O(log n)`
descent of the AVL tree, **not** a full traversal or in-order scan:

- An empty tree (`nil`) contributes `0`.
- At a node with coordinate `c`, delta `d`, and children `left`/`right`:
  - If `c <= point`, then every coordinate in `left` is also `<= point`, so add
    the entire left subtree's total via `sum_of/1`, add this node's own `d`, and
    recurse into `right` (which may hold further coordinates `<= point`).
  - Otherwise `c > point`, so this node and its whole `right` subtree are out of
    range; recurse only into `left`.

Use the existing `sum_of/1` aggregate helper rather than re-summing a subtree by
hand.

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
  defp prefix_sum(nil, _point) do
    # TODO
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