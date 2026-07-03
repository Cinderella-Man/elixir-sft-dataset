Implement the private `sort_items/3` function. It receives the filtered list of
item maps, the `field` atom to sort by (one of `:id`, `:name`, `:age`), and the
`order` atom (`:asc` or `:desc`). Sort the items ascending by the value at
`field`, using each item's `:id` as a deterministic tiebreak (so items with equal
sort-field values keep a stable, id-ascending order). If `order` is `:desc`,
reverse the ascending result; otherwise return it as-is.

```elixir
defmodule QueryPaginator do
  @moduledoc """
  Offset pagination over an in-memory list with multi-field sorting, filtering,
  and strict input validation. Returns `{:ok, result}` or `{:error, reason}`.
  """

  @default_page 1
  @default_page_size 20
  @max_page_size 100
  @sortable [:id, :name, :age]

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

  defp parse_sort(%{"sort" => raw}) do
    field = to_existing_atom_safe(raw)
    if field in @sortable, do: {:ok, field}, else: {:error, :invalid_sort_field}
  end

  defp parse_sort(_), do: {:ok, :id}

  defp parse_order(%{"order" => "asc"}), do: {:ok, :asc}
  defp parse_order(%{"order" => "desc"}), do: {:ok, :desc}
  defp parse_order(%{"order" => _}), do: {:error, :invalid_order}
  defp parse_order(_), do: {:ok, :asc}

  defp parse_filters(params) do
    with {:ok, min_age} <- parse_int_filter(params, "min_age"),
         {:ok, max_age} <- parse_int_filter(params, "max_age") do
      name_contains =
        case Map.get(params, "name_contains") do
          v when is_binary(v) -> v
          _ -> nil
        end

      {:ok, %{min_age: min_age, max_age: max_age, name_contains: name_contains}}
    end
  end

  defp parse_int_filter(params, key) do
    case Map.get(params, key) do
      nil ->
        {:ok, nil}

      raw ->
        case Integer.parse(to_string(raw)) do
          {n, ""} -> {:ok, n}
          _ -> {:error, :invalid_filter}
        end
    end
  end

  defp apply_filters(items, filters) do
    items
    |> maybe_filter(filters.min_age, fn i, v -> i.age >= v end)
    |> maybe_filter(filters.max_age, fn i, v -> i.age <= v end)
    |> maybe_filter(filters.name_contains, fn i, v ->
      String.contains?(String.downcase(i.name), String.downcase(v))
    end)
  end

  defp maybe_filter(items, nil, _fun), do: items
  defp maybe_filter(items, value, fun), do: Enum.filter(items, &fun.(&1, value))

  defp sort_items(items, field, order) do
    # TODO
  end

  defp to_existing_atom_safe(raw) when is_binary(raw) do
    String.to_existing_atom(raw)
  rescue
    ArgumentError -> nil
  end

  defp to_existing_atom_safe(_), do: nil

  defp parse_page(%{"page" => raw}) do
    case Integer.parse(to_string(raw)) do
      {n, _} when n >= 1 -> n
      _ -> @default_page
    end
  end

  defp parse_page(_), do: @default_page

  defp parse_page_size(%{"page_size" => raw}) do
    case Integer.parse(to_string(raw)) do
      {n, _} when n >= 1 -> min(n, @max_page_size)
      _ -> @default_page_size
    end
  end

  defp parse_page_size(_), do: @default_page_size
end
```