  defp ladder_value(ladder, strike_n) when strike_n >= 1 do
    idx = min(strike_n - 1, length(ladder) - 1)
    Enum.at(ladder, idx)
  end