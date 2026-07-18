  defp check(errors, field, value) do
    if present?(value), do: errors, else: Map.put(errors, field, ["can't be blank"])
  end