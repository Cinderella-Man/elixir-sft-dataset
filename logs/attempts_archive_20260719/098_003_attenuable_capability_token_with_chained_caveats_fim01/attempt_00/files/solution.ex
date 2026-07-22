  @spec satisfied?(binary(), binary(), context()) :: boolean()
  defp satisfied?("expires_at", value, context) do
    with {:ok, limit} <- parse_integer(value),
         now when is_integer(now) <- Map.get(context, :now) do
      now < limit
    else
      _other -> false
    end
  end

  defp satisfied?("action", value, context), do: Map.get(context, :action) === value

  defp satisfied?("resource_prefix", value, context) do
    case Map.get(context, :resource) do
      resource when is_binary(resource) -> String.starts_with?(resource, value)
      _other -> false
    end
  end

  defp satisfied?(_key, _value, _context), do: false