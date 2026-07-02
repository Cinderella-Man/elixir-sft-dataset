  defp select_tier(tiers, order_total) do
    tiers
    |> Enum.with_index()
    |> Enum.filter(fn {tier, _i} -> tier.threshold <= order_total end)
    |> case do
      [] -> :below_min_order
      qualifying -> Enum.max_by(qualifying, fn {tier, _i} -> tier.threshold end)
    end
  end