  defp weighted_rank(weighted, percentile) do
    # A sample whose weight has underflowed to exactly 0.0 contributes nothing
    # and must not be selectable — the same absence rule that makes an
    # all-underflowed series {:error, :empty} (a zero-weight sample would
    # otherwise win percentile 0.0, since 0.0 >= a target of 0.0).
    sorted =
      weighted
      |> Enum.reject(fn {_v, w} -> w == 0.0 end)
      |> Enum.sort_by(fn {v, _w} -> v end)

    total = Enum.reduce(sorted, 0.0, fn {_v, w}, acc -> acc + w end)

    if sorted == [] or total == 0.0 do
      {:error, :empty}
    else
      target = percentile * total

      {_cum, value} =
        Enum.reduce_while(sorted, {0.0, nil}, fn {v, w}, {cum, _last} ->
          cum2 = cum + w

          if cum2 >= target - @epsilon do
            {:halt, {cum2, v}}
          else
            {:cont, {cum2, v}}
          end
        end)

      {:ok, value}
    end
  end