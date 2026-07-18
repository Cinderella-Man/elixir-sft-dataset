  @doc """
  Paginate `items` according to `params`.

  `params` is a map of optional string keys: `"page"`, `"page_size"`, `"sort"`,
  `"order"`, `"min_age"`, `"max_age"`, and `"name_contains"`. Sorting, ordering,
  and filter inputs are validated first; invalid input returns a tagged
  `{:error, reason}` without partial data. On success returns
  `{:ok, %{data: [...], meta: %{...}}}`.
  """
  @spec paginate([map()], map()) :: {:ok, %{data: [map()], meta: map()}} | {:error, atom()}
  def paginate(items, params \\ %{}) when is_list(items) do
    with {:ok, sort} <- parse_sort(params),
         {:ok, order} <- parse_order(params),
         {:ok, filters} <- parse_filters(params) do
      page = parse_page(params)
      page_size = parse_page_size(params)

      filtered = apply_filters(items, filters)
      total_count = length(filtered)
      total_pages = if total_count == 0, do: 0, else: ceil(total_count / page_size)

      data =
        filtered
        |> sort_items(sort, order)
        |> Enum.drop((page - 1) * page_size)
        |> Enum.take(page_size)

      {:ok,
       %{
         data: data,
         meta: %{
           current_page: page,
           page_size: page_size,
           total_count: total_count,
           total_pages: total_pages,
           sort: sort,
           order: order,
           filters: filters
         }
       }}
    end
  end