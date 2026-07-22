Implement the private `parse_page_size/1` function for the `QueryPaginator` module below.

`parse_page_size/1` takes the `params` map and returns an integer page size. When the map has a `"page_size"` key, parse its value as an integer (the raw value may be a string or a number, so convert it with `to_string/1` before parsing). If it parses to a value `>= 1`, clamp it to a maximum of `@max_page_size` (100) and return that; otherwise — a non-numeric value or a value `< 1` — fall back to `@default_page_size` (20). When `"page_size"` is absent, return `@default_page_size`. Implement it with two function clauses (one matching a map containing `"page_size"`, one catch-all), mirroring the style of `parse_page/1`.

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
    sorted = Enum.sort_by(items, &{Map.get(&1, field), &1.id})
    if order == :desc, do: Enum.reverse(sorted), else: sorted
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

  defp parse_page_size(params) do
    # TODO
  end
end
```