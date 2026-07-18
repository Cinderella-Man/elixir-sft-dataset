# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule MaxOverlapIntervalTree do
  # Sentinel standing in for "no elements" when combining `best` aggregates.
  # Any real running prefix sum is far larger than this.
  @neg_inf -1_000_000_000_000_000

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def new(), do: nil

  def insert(tree, {start, finish}) do
    tree
    |> bump(start, 1)
    |> bump(finish + 1, -1)
  end

  def depth_at(tree, point), do: prefix_sum(tree, point)

  def max_overlap(nil), do: 0
  def max_overlap(%{best: best}), do: max(0, best)

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

  defp sum_of(nil), do: 0
  defp sum_of(%{sum: s}), do: s

  defp best_of(nil), do: @neg_inf
  defp best_of(%{best: b}), do: b

  defp height(nil), do: 0
  defp height(%{height: h}), do: h

  # Build a node, recomputing `sum`, `best`, and `height` from the children.
  #
  # For the in-order sequence [left..., node, right...], the maximum running
  # prefix sum is the best of:
  #   * a prefix ending inside `left`            -> best_of(left)
  #   * the prefix ending exactly at `node`      -> sum_of(left) + delta
  #   * a prefix ending inside `right`           -> sum_of(left) + delta + best_of(right)
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

  defp balance_factor(nil), do: 0
  defp balance_factor(%{left: l, right: r}), do: height(l) - height(r)

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

  defp prefix_sum(nil, _point), do: 0

  defp prefix_sum(%{coord: c, delta: d, left: left, right: right}, point) do
    if c <= point do
      sum_of(left) + d + prefix_sum(right, point)
    else
      prefix_sum(left, point)
    end
  end

  # ---------------------------------------------------------------------------
  # In-order flattening (ascending coordinate order) for busiest_point/1.
  # ---------------------------------------------------------------------------

  defp in_order(nil, acc), do: acc

  defp in_order(%{coord: c, delta: d, left: left, right: right}, acc) do
    in_order(left, [{c, d} | in_order(right, acc)])
  end
end
```
