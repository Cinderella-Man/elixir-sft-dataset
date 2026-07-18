  defp put_field(values, _field, :missing), do: values
  defp put_field(values, field, value), do: Map.put(values, field, value)