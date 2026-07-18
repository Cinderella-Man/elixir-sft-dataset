  defp valid_tiers?(tiers) when is_list(tiers) and tiers != [] do
    Enum.all?(tiers, &valid_tier?/1) and ascending?(Enum.map(tiers, & &1.threshold))
  end

  defp valid_tiers?(_), do: false