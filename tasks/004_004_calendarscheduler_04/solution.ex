# Find the first datetime strictly greater than `after_ndt` that matches
# `rule`, walking month-by-month.  We bound the walk at 60 months (5 years)
# to prevent infinite loops on malformed rules, though validated rules
# should always match within at most 12 months.
defp compute_next_run(rule, after_ndt) do
  walk_months(rule, after_ndt, after_ndt.year, after_ndt.month, 60)
end
