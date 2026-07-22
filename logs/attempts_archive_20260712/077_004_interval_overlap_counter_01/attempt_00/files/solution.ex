defmodule IntervalCounter do
  @moduledoc """
  A persistent, purely-functional interval tree specialized for aggregate
  counting rather than enumeration.

  It keeps an augmented AVL tree (each node caches the maximum `finish` in its
  subtree) so `count_overlapping/2` and `count_enclosing/2` prune branches while
  tallying a count instead of collecting intervals. `max_concurrent/1` computes
  peak concurrency with a sweep-line over all stored intervals.

  Two intervals overlap when they share at least one point, so `{1, 3}` and
  `{3, 5}` overlap (peak concurrency 2), while `{1, 2}` and `{3, 4}` do not.
  Every `insert/2` returns a new value; inputs are never mutated.
  """

  @type interval :: {integer(), integer()}
  @type t :: nil | map()

  # -------------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------------

  @spec new() :: t()
  def new(), do: nil

  @spec insert(t(), interval()) :: t()
  def insert(tree, {s, f} = interval) when is_integer(s) and is_integer(f) and s <= f do
    do_insert(tree, interval)
  end

  @spec count_overlapping(t(), interval()) :: non_neg_integer()
  def count_overlapping(nil, _query), do: 0
  def count_overlapping(tree, {qs, qf}), do: do_count_overlap(tree, qs, qf, 0)

  @spec count_enclosing(t(), integer()) :: non_neg_integer()
  def count_enclosing(nil, _point), do: 0
  def count_enclosing(tree, point) when is_integer(point), do: do_count_enclose(tree, point, 0)

  @spec max_concurrent(t()) :: non_neg_integer()
  def max_concurrent(nil), do: 0

  def max_concurrent(tree) do
    events =
      tree
      |> to_list([])
      |> Enum.flat_map(fn {s, f} -> [{s, 1}, {f + 1, -1}] end)
      |> Enum.sort()

    {best, _cur} =
      Enum.reduce(events, {0, 0}, fn {_pos, delta}, {best, cur} ->
        cur = cur + delta
        {max(best, cur), cur}
      end)

    best
  end

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
  # Insertion (ordered by start; duplicates allowed)
  # -------------------------------------------------------------------------

  defp do_insert(nil, interval), do: make_node(interval, nil, nil)

  defp do_insert(%{interval: {ns, _nf}} = node, {s, _f} = interval) do
    updated =
      if s <= ns do
        make_node(node.interval, do_insert(node.left, interval), node.right)
      else
        make_node(node.interval, node.left, do_insert(node.right, interval))
      end

    rebalance(updated)
  end

  # -------------------------------------------------------------------------
  # Counting overlap query (pruned)
  # -------------------------------------------------------------------------

  defp do_count_overlap(nil, _qs, _qf, acc), do: acc
  defp do_count_overlap(%{max_finish: mf}, qs, _qf, acc) when mf < qs, do: acc

  defp do_count_overlap(%{interval: {s, f}, left: left, right: right}, qs, qf, acc) do
    acc = if s <= qf and f >= qs, do: acc + 1, else: acc
    acc = do_count_overlap(left, qs, qf, acc)

    if s <= qf do
      do_count_overlap(right, qs, qf, acc)
    else
      acc
    end
  end

  # -------------------------------------------------------------------------
  # Counting enclosing query / stabbing count (pruned)
  # -------------------------------------------------------------------------

  defp do_count_enclose(nil, _point, acc), do: acc
  defp do_count_enclose(%{max_finish: mf}, point, acc) when mf < point, do: acc

  defp do_count_enclose(%{interval: {s, f}, left: left, right: right}, point, acc) do
    acc = if s <= point and point <= f, do: acc + 1, else: acc
    acc = do_count_enclose(left, point, acc)

    if s <= point do
      do_count_enclose(right, point, acc)
    else
      acc
    end
  end

  # -------------------------------------------------------------------------
  # Traversal / size
  # -------------------------------------------------------------------------

  defp to_list(nil, acc), do: acc

  defp to_list(%{interval: iv, left: l, right: r}, acc) do
    to_list(l, [iv | to_list(r, acc)])
  end

  defp do_size(nil), do: 0
  defp do_size(%{left: l, right: r}), do: 1 + do_size(l) + do_size(r)
end