  # Advance to the top of the next hour.
  defp next_hour(dt) do
    dt
    |> Map.put(:minute, 0)
    |> NaiveDateTime.add(3_600, :second)
    |> Map.put(:minute, 0)
    |> Map.put(:second, 0)
  end