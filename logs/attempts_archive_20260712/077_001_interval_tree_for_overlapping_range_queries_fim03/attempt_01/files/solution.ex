  @spec do_enclosing(t(), integer(), [interval()]) :: [interval()]
  defp do_enclosing(nil, _point, acc), do: acc

  # Prune rule 1: entire subtree finishes before the point.
  defp do_enclosing(%{max_finish: mf}, point, acc) when mf < point, do: acc

  defp do_enclosing(%{interval: {s, f} = iv, left: left, right: right}, point, acc) do
    # Check current node
    acc = if s <= point and point <= f, do: [iv | acc], else: acc

    # Always recurse left (guarded by max_finish above).
    acc = do_enclosing(left, point, acc)

    # Prune rule 2: right subtree starts are all >= s; skip if s > point.
    if s <= point do
      do_enclosing(right, point, acc)
    else
      acc
    end
  end