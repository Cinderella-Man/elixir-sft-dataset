  defp do_enclosing(nil, _point, acc), do: acc

  # Prune rule 1: no interval in this subtree reaches far enough right to
  # contain the point.
  defp do_enclosing(%{max_finish: mf}, point, acc) when mf < point, do: acc

  defp do_enclosing(%{interval: {s, f} = iv, left: left, right: right}, point, acc) do
    # Add the node's own interval iff it encloses the point.
    acc = if s <= point and point <= f, do: [iv | acc], else: acc

    # Always recurse left (already guarded by max_finish above).
    acc = do_enclosing(left, point, acc)

    # Prune rule 2: right subtree starts are all >= s; skip if s > point.
    if s <= point do
      do_enclosing(right, point, acc)
    else
      acc
    end
  end