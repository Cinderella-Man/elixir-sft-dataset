  def search(products, params \\ %{}) when is_list(products) and is_map(params) do
    with :ok <- validate_sort(params),
         {:ok, cursor} <- decode_cursor(params, sort_field(params)) do
      sorted =
        products
        |> Enum.filter(&matches?(&1, params))
        |> Enum.sort(sorter(params))

      after_cursor =
        case cursor do
          nil ->
            sorted

          key ->
            Enum.drop_while(sorted, fn p ->
              compare_key(order(params), key_of(p, params), key) != :after
            end)
        end

      limit = limit(params)
      page = Enum.take(after_cursor, limit)
      remaining = length(after_cursor) - length(page)

      next =
        if remaining > 0 and page != [] do
          encode_cursor(List.last(page), params)
        else
          nil
        end

      {:ok, %{data: Enum.map(page, &render/1), next_cursor: next, has_more: remaining > 0}}
    end
  end