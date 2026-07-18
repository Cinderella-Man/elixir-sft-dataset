  defp valid_rule?({:nth_weekday_of_month, n, wd, {h, m}})
       when is_integer(n) and n in 1..4 and is_integer(h) and h in 0..23 and
              is_integer(m) and m in 0..59 do
    Map.has_key?(@weekdays, wd)
  end

  defp valid_rule?({:last_weekday_of_month, wd, {h, m}})
       when is_integer(h) and h in 0..23 and is_integer(m) and m in 0..59 do
    Map.has_key?(@weekdays, wd)
  end

  defp valid_rule?({:nth_day_of_month, d, {h, m}})
       when is_integer(d) and d in 1..31 and is_integer(h) and h in 0..23 and
              is_integer(m) and m in 0..59 do
    true
  end

  defp valid_rule?({:last_day_of_month, {h, m}})
       when is_integer(h) and h in 0..23 and is_integer(m) and m in 0..59 do
    true
  end

  defp valid_rule?(_), do: false