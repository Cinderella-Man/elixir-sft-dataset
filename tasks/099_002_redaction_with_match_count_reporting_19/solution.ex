  @spec merge(report(), report()) :: report()
  defp merge(a, b), do: Map.merge(a, b, fn _k, v1, v2 -> v1 + v2 end)