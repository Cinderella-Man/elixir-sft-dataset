  defp t_stab_count(nil, _point, acc), do: acc
  defp t_stab_count(%{max_finish: mf}, point, acc) when mf < point, do: acc

  defp t_stab_count(%{s: s, f: f, left: l, right: r}, point, acc) do
    acc = if s <= point and point <= f, do: acc + 1, else: acc
    acc = t_stab_count(l, point, acc)

    if s <= point, do: t_stab_count(r, point, acc), else: acc
  end