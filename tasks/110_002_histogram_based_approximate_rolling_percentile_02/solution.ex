  defp quantile(counts, edges_t, k, percentile) do
    list = for i <- 0..(k - 1), do: Map.get(counts, i, 0)
    n = Enum.sum(list)

    if n == 0 do
      {:error, :empty}
    else
      target = percentile * n

      {value, _} =
        Enum.reduce_while(0..(k - 1), {nil, 0}, fn i, {_last, cum_before} ->
          c = Enum.at(list, i)
          cum = cum_before + c

          if cum >= target or i == k - 1 do
            lo = elem(edges_t, i)
            hi = elem(edges_t, i + 1)
            frac = if c == 0, do: 0.0, else: (target - cum_before) / c
            frac = frac |> max(0.0) |> min(1.0)
            {:halt, {lo + (hi - lo) * frac, cum}}
          else
            {:cont, {nil, cum}}
          end
        end)

      {:ok, value * 1.0}
    end
  end