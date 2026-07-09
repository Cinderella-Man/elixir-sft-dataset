# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

  defp parse_page_size(%{"page_size" => raw}) do
    case Integer.parse(to_string(raw)) do
      {n, _} when n >= 1 -> min(n, @max_page_size)
      _ -> @default_page_size
    end
  end

  defp parse_page_size(_), do: @default_page_size
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule QueryPaginatorTest do
  use ExUnit.Case, async: false

  defp items do
    [
      %{id: 1, name: "Alice", age: 30},
      %{id: 2, name: "bob", age: 25},
      %{id: 3, name: "Carol", age: 40},
      %{id: 4, name: "dave", age: 25},
      %{id: 5, name: "Eve", age: 35},
      %{id: 6, name: "amanda", age: 22}
    ]
  end

  test "defaults sort by id ascending with default paging" do
    assert {:ok, %{data: data, meta: meta}} = QueryPaginator.paginate(items())
    assert Enum.map(data, & &1.id) == [1, 2, 3, 4, 5, 6]
    assert meta.current_page == 1
    assert meta.page_size == 20
    assert meta.total_count == 6
    assert meta.total_pages == 1
    assert meta.sort == :id
    assert meta.order == :asc
    assert meta.filters == %{min_age: nil, max_age: nil, name_contains: nil}
  end

  test "sorts by name ascending and descending with id tiebreak" do
    {:ok, %{data: asc}} = QueryPaginator.paginate(items(), %{"sort" => "name", "order" => "asc"})
    assert Enum.map(asc, & &1.name) == ["Alice", "Carol", "Eve", "amanda", "bob", "dave"]

    {:ok, %{data: desc}} =
      QueryPaginator.paginate(items(), %{"sort" => "name", "order" => "desc"})

    assert Enum.map(desc, & &1.name) ==
             Enum.reverse(["Alice", "Carol", "Eve", "amanda", "bob", "dave"])
  end

  test "sorts by age using id as tiebreak" do
    # TODO
  end

  test "rejects an invalid sort field" do
    assert {:error, :invalid_sort_field} = QueryPaginator.paginate(items(), %{"sort" => "email"})
  end

  test "rejects an invalid order" do
    assert {:error, :invalid_order} = QueryPaginator.paginate(items(), %{"order" => "sideways"})
  end

  test "min_age and max_age filters affect total_count and pages" do
    {:ok, %{data: data, meta: meta}} =
      QueryPaginator.paginate(items(), %{"min_age" => "25", "max_age" => "35", "page_size" => "2"})

    assert meta.total_count == 4
    assert meta.total_pages == 2
    assert length(data) == 2
    assert Enum.all?(data, &(&1.age >= 25 and &1.age <= 35))
  end

  test "name_contains is case-insensitive" do
    {:ok, %{data: data, meta: meta}} =
      QueryPaginator.paginate(items(), %{"name_contains" => "A"})

    names = Enum.map(data, & &1.name)
    assert "Alice" in names
    assert "Carol" in names
    assert "amanda" in names
    assert "dave" in names
    assert meta.total_count == length(data)
    assert meta.filters.name_contains == "A"
  end

  test "rejects a non-integer age filter" do
    assert {:error, :invalid_filter} = QueryPaginator.paginate(items(), %{"min_age" => "old"})
    assert {:error, :invalid_filter} = QueryPaginator.paginate(items(), %{"max_age" => "12x"})
  end

  test "clamps page_size and coerces bad page" do
    {:ok, %{meta: meta}} =
      QueryPaginator.paginate(items(), %{"page_size" => "500", "page" => "abc"})

    assert meta.page_size == 100
    assert meta.current_page == 1
  end

  test "page beyond total returns empty data with correct meta" do
    {:ok, %{data: data, meta: meta}} =
      QueryPaginator.paginate(items(), %{"page" => "99", "page_size" => "2"})

    assert data == []
    assert meta.current_page == 99
    assert meta.total_count == 6
    assert meta.total_pages == 3
  end

  test "empty items yields zero total_pages" do
    {:ok, %{data: data, meta: meta}} = QueryPaginator.paginate([])
    assert data == []
    assert meta.total_count == 0
    assert meta.total_pages == 0
  end
end
```
