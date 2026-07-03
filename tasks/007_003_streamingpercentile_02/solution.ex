  defp quantile([only], _q), do: only

  defp quantile(sorted, q) do
    n = length(sorted)
    rank = q * (n - 1)

    lo_idx = trunc(rank)
    hi_idx = min(lo_idx + 1, n - 1)

    lo_val = Enum.at(sorted, lo_idx)

    if lo_idx == hi_idx do
      lo_val
    else
      hi_val = Enum.at(sorted, hi_idx)
      frac = rank - lo_idx
      lo_val + frac * (hi_val - lo_val)
    end
  end