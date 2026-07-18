  defp parse_cursor(%{"cursor" => raw}) when is_binary(raw) do
    case decode_cursor(raw) do
      {:ok, n} -> n
      :error -> nil
    end
  end

  defp parse_cursor(_), do: nil