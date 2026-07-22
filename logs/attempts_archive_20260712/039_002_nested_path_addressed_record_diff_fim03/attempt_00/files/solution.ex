  defp join("", field), do: to_string(field)
  defp join(prefix, field), do: prefix <> "." <> to_string(field)