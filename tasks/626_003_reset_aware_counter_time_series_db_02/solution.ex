  @spec reset_aware_increase([point()]) :: number()
  defp reset_aware_increase(points) do
    points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0, fn [{_pts, prev}, {_cts, cur}], acc ->
      delta = if cur >= prev, do: cur - prev, else: cur
      acc + delta
    end)
  end