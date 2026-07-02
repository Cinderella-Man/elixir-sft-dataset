  defp bucket_index(value, edges_t, k) do
    lo = elem(edges_t, 0)
    hi = elem(edges_t, k)
    v = value |> max(lo) |> min(hi)

    Enum.reduce_while(0..(k - 1), k - 1, fn i, _acc ->
      upper = elem(edges_t, i + 1)
      if v < upper, do: {:halt, i}, else: {:cont, min(i + 1, k - 1)}
    end)
  end