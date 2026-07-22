  defp project(inc, :delta, _interval_ms), do: inc
  defp project(inc, :rate, interval_ms), do: inc / (interval_ms / 1000)