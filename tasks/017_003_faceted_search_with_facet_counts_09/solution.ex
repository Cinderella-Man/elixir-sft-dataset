  defp name_match?(p, %{"name" => n}) when is_binary(n) and n != "" do
    String.contains?(String.downcase(p.name), String.downcase(n))
  end

  defp name_match?(_, _), do: true