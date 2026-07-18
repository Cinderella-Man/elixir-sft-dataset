  defp t_min(%{left: nil} = node), do: node
  defp t_min(%{left: l}), do: t_min(l)