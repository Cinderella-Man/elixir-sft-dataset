  def search(products, params \\ %{}) when is_list(products) and is_map(params) do
    if invalid_sort?(params) do
      {:error, :invalid_sort_field}
    else
      name_p = &name_match?(&1, params)
      price_p = &price_match?(&1, params)
      cat_p = &category_match?(&1, params)
      tags_p = &tags_match?(&1, params)

      full =
        Enum.filter(products, fn p ->
          name_p.(p) and price_p.(p) and cat_p.(p) and tags_p.(p)
        end)

      # Source for a facet excludes ONLY that facet's own filter.
      cat_source =
        Enum.filter(products, fn p -> name_p.(p) and price_p.(p) and tags_p.(p) end)

      tag_source =
        Enum.filter(products, fn p -> name_p.(p) and price_p.(p) and cat_p.(p) end)

      facets = %{
        categories: category_facets(cat_source),
        tags: tag_facets(tag_source)
      }

      data =
        full
        |> Enum.sort(sorter(params))
        |> Enum.map(&render/1)

      {:ok, %{data: data, facets: facets, total: length(full)}}
    end
  end