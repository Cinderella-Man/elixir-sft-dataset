defp walk_months(_rule, _after, _year, _month, 0) do
  # Defensive fallback — should never fire for validated rules.
  raise "CalendarScheduler: rule did not match in 60 months — malformed rule?"
end

defp walk_months(rule, after_ndt, year, month, budget) do
  case target_in_month(rule, year, month) do
    {:ok, candidate} ->
      if NaiveDateTime.compare(candidate, after_ndt) == :gt do
        candidate
      else
        {next_year, next_month} = bump_month(year, month)
        walk_months(rule, after_ndt, next_year, next_month, budget - 1)
      end

    :no_match ->
      {next_year, next_month} = bump_month(year, month)
      walk_months(rule, after_ndt, next_year, next_month, budget - 1)
  end
end
