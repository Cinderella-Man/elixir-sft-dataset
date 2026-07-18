  def search(products, params \\ %{}) when is_list(products) and is_map(params) do
    if invalid_sort?(params) do
      {:error, :invalid_sort_field}
    else
      query = tokenize(Map.get(params, "q"))

      filtered =
        Enum.filter(products, fn p ->
          category_match?(p, params) and price_match?(p, params)
        end)

      scored = Enum.map(filtered, fn p -> {p, score(p, query)} end)

      scored =
        if query == [] do
          scored
        else
          Enum.filter(scored, fn {_p, s} -> s > 0 end)
        end

      sort = Map.get(params, "sort", "relevance")
      order = Map.get(params, "order")
      sorted = Enum.sort(scored, comparator(sort, order))

      {:ok, %{data: Enum.map(sorted, fn {p, s} -> render(p, s) end)}}
    end
  end