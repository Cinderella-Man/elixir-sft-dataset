  defp merge(base, []), do: base
  defp merge(base, kw), do: struct(base, kw)