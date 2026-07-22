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