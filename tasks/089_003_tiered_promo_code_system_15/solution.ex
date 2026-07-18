  defp fetch_tier(code, order_total) do
    case select_tier(code.tiers, order_total) do
      :below_min_order -> {:error, :below_min_order}
      {tier, index} -> {:ok, tier, index}
    end
  end