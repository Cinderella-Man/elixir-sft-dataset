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

      # The float tolerance must scale WITH the weights: an absolute epsilon
      # dwarfs the whole distribution once a series has aged 30+ half-lives
      # (total < 1.0e-9 yet nonzero), making the first sample win every
      # percentile. Relative to total, the comparison is invariant under
      # uniform aging — the prompt's neutrality rule.
      tolerance = @epsilon * total

      {_cum, value} =
        Enum.reduce_while(sorted, {0.0, nil}, fn {v, w}, {cum, _last} ->
          cum2 = cum + w

          if cum2 >= target - tolerance do
            {:halt, {cum2, v}}
          else
            {:cont, {cum2, v}}
          end
        end)

      {:ok, value}
    end
  end