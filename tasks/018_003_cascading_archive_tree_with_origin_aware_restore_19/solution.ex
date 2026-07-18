  defp validate_content(content) when is_binary(content), do: {:ok, content}
  defp validate_content(_content), do: {:ok, ""}