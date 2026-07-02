defp valid_tier?(%{threshold: t, type: type, value: v})
     when is_integer(t) and t >= 0 and is_number(v) and type in @tier_types do
  case type do
    :percentage -> v >= 0 and v <= 100
    :fixed_amount -> v >= 0
  end
end

defp valid_tier?(_), do: false