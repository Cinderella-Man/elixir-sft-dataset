  defp increment(v0, v1, :raw), do: v1 - v0

  defp increment(v0, v1, :detect) do
    if v1 < v0, do: v1, else: v1 - v0
  end