  defp t_enclosing(nil, _point, acc), do: acc
  defp t_enclosing(%{max_finish: mf}, point, acc) when mf < point, do: acc

  defp t_enclosing(%{s: s, f: f, left: l, right: r}, point, acc) do
    acc = if s <= point and point <= f, do: [{s, f} | acc], else: acc
    acc = t_enclosing(l, point, acc)

    if s <= point, do: t_enclosing(r, point, acc), else: acc
  end