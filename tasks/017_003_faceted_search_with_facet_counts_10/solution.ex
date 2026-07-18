  defp category_match?(p, %{"categories" => cats}) when is_list(cats) and cats != [] do
    p.category in cats
  end

  defp category_match?(_, _), do: true