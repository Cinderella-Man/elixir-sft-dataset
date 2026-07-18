  defp strip_prefix(str, prefix) do
    String.replace_prefix(str, prefix, "")
  end