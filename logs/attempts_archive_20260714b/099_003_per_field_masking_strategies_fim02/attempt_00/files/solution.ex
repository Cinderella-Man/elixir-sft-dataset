  @spec last4(term()) :: String.t()
  defp last4(value) when is_binary(value) do
    len = String.length(value)

    if len <= 4 do
      String.duplicate("*", len)
    else
      String.duplicate("*", len - 4) <> String.slice(value, len - 4, 4)
    end
  end

  defp last4(_value), do: "[MASKED]"