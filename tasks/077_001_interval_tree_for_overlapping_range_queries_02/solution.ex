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