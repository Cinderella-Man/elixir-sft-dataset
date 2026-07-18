  defp empty_value(_mode, _interval_ms, nil), do: nil
  defp empty_value(mode, interval_ms, :zero), do: project(0, mode, interval_ms)