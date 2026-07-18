  # Advance to midnight of the next day.
  defp next_day(dt) do
    dt
    |> NaiveDateTime.add(86_400, :second)
    |> Map.merge(%{hour: 0, minute: 0, second: 0})
  end