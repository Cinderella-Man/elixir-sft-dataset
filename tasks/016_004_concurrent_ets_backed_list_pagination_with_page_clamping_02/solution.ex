def list(table, params \\ %{}) do
  page_size = parse_page_size(params)
  requested = parse_page(params)

  all =
    table
    |> :ets.tab2list()
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))

  total_count = length(all)
  total_pages = if total_count == 0, do: 0, else: ceil(total_count / page_size)

  current =
    cond do
      total_count == 0 -> 1
      requested > total_pages -> total_pages
      true -> requested
    end

  data =
    all
    |> Enum.drop((current - 1) * page_size)
    |> Enum.take(page_size)

  %{
    data: data,
    meta: %{
      requested_page: requested,
      current_page: current,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages
    }
  }
end