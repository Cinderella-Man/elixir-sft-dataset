  defp t_bf(nil), do: 0
  defp t_bf(%{left: l, right: r}), do: t_height(l) - t_height(r)