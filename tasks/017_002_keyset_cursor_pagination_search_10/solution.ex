  defp matches?(p, params) do
    name_match?(p, params) and category_match?(p, params) and price_match?(p, params)
  end