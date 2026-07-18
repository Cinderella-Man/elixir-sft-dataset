  defp convert(micros, :microsecond), do: micros
  defp convert(micros, :millisecond), do: div(micros, 1_000)
  defp convert(micros, :second), do: div(micros, 1_000_000)
  defp convert(micros, :nanosecond), do: micros * 1_000