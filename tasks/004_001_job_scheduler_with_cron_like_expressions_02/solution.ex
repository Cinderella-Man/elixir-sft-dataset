defp scan(parsed, candidate, iteration) do
  cond do
    # Month mismatch → advance to the first day of the next matching month.
    not MapSet.member?(parsed.month, candidate.month) ->
      scan(parsed, advance_to_next_month(parsed, candidate), iteration + 1)

    # Day-of-month mismatch → advance to next day at 00:00.
    not MapSet.member?(parsed.day, candidate.day) ->
      scan(parsed, next_day(candidate), iteration + 1)

    # Day-of-week mismatch → advance to next day at 00:00.
    not MapSet.member?(parsed.weekday, day_of_week(candidate)) ->
      scan(parsed, next_day(candidate), iteration + 1)

    # Hour mismatch → advance to next hour at :00.
    not MapSet.member?(parsed.hour, candidate.hour) ->
      scan(parsed, next_hour(candidate), iteration + 1)

    # Minute mismatch → advance one minute.
    not MapSet.member?(parsed.minute, candidate.minute) ->
      scan(parsed, NaiveDateTime.add(candidate, 60, :second), iteration + 1)

    # All fields match!
    true ->
      candidate
  end
end
