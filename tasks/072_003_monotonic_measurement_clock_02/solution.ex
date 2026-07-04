  defp duration_to_micros(duration) do
    Enum.reduce(duration, 0, fn {unit, amount}, acc ->
      acc + amount * Map.fetch!(@unit_micros, unit)
    end)
  end