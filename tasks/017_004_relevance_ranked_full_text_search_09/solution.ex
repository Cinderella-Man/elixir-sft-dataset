  defp category_match?(p, %{"category" => c}) when is_binary(c) and c != "" do
    p.category == c
  end

  defp category_match?(_, _), do: true