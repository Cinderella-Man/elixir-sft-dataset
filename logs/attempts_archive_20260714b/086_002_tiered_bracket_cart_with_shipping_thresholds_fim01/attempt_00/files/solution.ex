defp discount_for(quantity, tiers) do
  tiers
  |> Enum.filter(fn {min, _rate} -> quantity >= min end)
  |> case do
    [] -> 0.0
    applicable -> applicable |> Enum.max_by(fn {min, _rate} -> min end) |> elem(1)
  end
end