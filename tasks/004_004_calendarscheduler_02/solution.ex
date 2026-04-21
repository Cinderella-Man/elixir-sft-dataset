# For each rule type, compute the target datetime within the given
# {year, month}, or return :no_match if the rule has no target there.
defp target_in_month({:nth_weekday_of_month, n, wd, {h, m}}, year, month) do
  target_dow = @weekdays[wd]
  first = Date.new!(year, month, 1)
  first_dow = Date.day_of_week(first)

  # Days from the 1st to the first occurrence of the target weekday (0..6).
  days_to_first = rem(target_dow - first_dow + 7, 7)
  nth_day = 1 + days_to_first + (n - 1) * 7

  if nth_day <= Calendar.ISO.days_in_month(year, month) do
    {:ok, NaiveDateTime.new!(year, month, nth_day, h, m, 0)}
  else
    :no_match
  end
end

defp target_in_month({:last_weekday_of_month, wd, {h, m}}, year, month) do
  target_dow = @weekdays[wd]
  last_day_num = Calendar.ISO.days_in_month(year, month)
  last_date = Date.new!(year, month, last_day_num)
  last_dow = Date.day_of_week(last_date)

  # Steps back from the last day to the most recent target weekday (0..6).
  steps_back = rem(last_dow - target_dow + 7, 7)
  day = last_day_num - steps_back

  {:ok, NaiveDateTime.new!(year, month, day, h, m, 0)}
end

defp target_in_month({:nth_day_of_month, day, {h, m}}, year, month) do
  if day <= Calendar.ISO.days_in_month(year, month) do
    {:ok, NaiveDateTime.new!(year, month, day, h, m, 0)}
  else
    :no_match
  end
end

defp target_in_month({:last_day_of_month, {h, m}}, year, month) do
  last = Calendar.ISO.days_in_month(year, month)
  {:ok, NaiveDateTime.new!(year, month, last, h, m, 0)}
end
