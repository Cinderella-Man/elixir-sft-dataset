  # An in-range expression is satisfiable iff some allowed (month, day) pair
  # can exist on a calendar: the day must not exceed the longest length that
  # month ever has (29 for February — leap years exist). Minute, hour, and
  # weekday fields can never make an in-range expression unsatisfiable on
  # their own, since every valid calendar date falls on every weekday across
  # years. Without this check, `next_run_time/2` would scan until its
  # iteration cap and raise inside the server.
  defp satisfiable?(parsed) do
    Enum.any?(parsed.month, fn month ->
      Enum.any?(parsed.day, fn day -> day <= max_month_day(month) end)
    end)
  end