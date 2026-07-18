  defp normalize_value(""), do: nil
  defp normalize_value(v), do: String.trim(v)