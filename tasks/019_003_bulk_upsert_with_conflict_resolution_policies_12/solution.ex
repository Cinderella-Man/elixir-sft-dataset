  defp put_qty_error(errors, attrs) do
    case Map.get(attrs, "qty") do
      nil -> errors
      q when is_integer(q) and q >= 0 -> errors
      _ -> Map.put(errors, "qty", ["must be a non-negative integer"])
    end
  end