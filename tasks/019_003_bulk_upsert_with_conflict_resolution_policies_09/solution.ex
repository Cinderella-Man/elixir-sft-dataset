  defp put_sku_error(errors, attrs) do
    case attrs["sku"] do
      s when is_binary(s) and byte_size(s) > 0 -> errors
      _ -> Map.put(errors, "sku", ["can't be blank"])
    end
  end