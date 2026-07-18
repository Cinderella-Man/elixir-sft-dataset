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
defmodule DeletableIntervalTree do
  # Weight-balance parameters. A subtree may be at most `@delta` times heavier
  # than its sibling; `@ratio` decides between a single and a double rotation.
  @delta 3
  @ratio 2

  # -------------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------------

  def new(), do: nil

  def insert(tree, {s, f} = interval) when is_integer(s) and is_integer(f) and s <= f do
    do_insert(tree, interval)
  end

  def member?(tree, {_s, _f} = interval), do: do_member?(tree, interval)

  def delete(tree, {_s, _f} = interval) do
    case do_delete(tree, interval) do
      {new_tree, true} -> {:ok, new_tree}
      {_unchanged, false} -> {:error, :not_found}
    end
  end

  def overlapping(nil, _query), do: []
  def overlapping(tree, {qs, qf}), do: do_overlapping(tree, qs, qf, [])

  def enclosing(nil, _point), do: []
  def enclosing(tree, point) when is_integer(point), do: do_enclosing(tree, point, [])

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
