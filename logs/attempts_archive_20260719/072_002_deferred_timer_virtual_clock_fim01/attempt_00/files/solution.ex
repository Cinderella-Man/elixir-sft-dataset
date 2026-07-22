  defp apply_duration(datetime, duration) do
    total =
      Enum.reduce(duration, 0, fn {unit, amount}, acc ->
        acc + amount * Map.fetch!(@unit_seconds, unit)
      end)

    DateTime.add(datetime, total, :second)
  end