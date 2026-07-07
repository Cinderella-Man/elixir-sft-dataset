  defp t_overlapping(%{s: s, f: f, left: l, right: r}, qs, qf, acc) do
    acc = if s <= qf and f >= qs, do: [{s, f} | acc], else: acc
    acc = t_overlapping(l, qs, qf, acc)

    if s <= qf, do: t_overlapping(r, qs, qf, acc), else: acc
  end