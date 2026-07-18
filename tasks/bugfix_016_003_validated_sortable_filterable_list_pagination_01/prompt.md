# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me a self-contained Elixir module `QueryPaginator` that implements **offset pagination with multi-field sorting, filtering, and strict validation**. This is the query core of a `GET /api/items` list endpoint, implemented as a pure function over an in-memory list so it can be tested without a database. Unlike a plain paginator, this one validates its inputs and returns tagged error tuples on bad requests instead of silently coercing them.

Each item is a map with `:id` (integer), `:name` (string), and `:age` (integer).

I need `paginate(items, params)` returning `{:ok, %{data: [...], meta: %{...}}}` or `{:error, reason}`, where `params` is a map with optional string keys:

- `"page"` — default `1`; values `< 1` or non-numeric fall back to `1`.
- `"page_size"` — default `20`; clamp to a maximum of `100`; values `< 1` or non-numeric fall back to `20`.
- `"sort"` — the field to sort by. Allowed fields are exactly `"id"`, `"name"`, `"age"`. Any other value returns `{:error, :invalid_sort_field}`. Default `:id`.
- `"order"` — `"asc"` (default) or `"desc"`. Any other value returns `{:error, :invalid_order}`.
- `"min_age"` / `"max_age"` — optional integer filters, each an inclusive bound on `:age` (an item passes when `age >= min_age` and `age <= max_age`). A present-but-non-integer value returns `{:error, :invalid_filter}`.
- `"name_contains"` — optional case-insensitive substring filter on `:name`.

Validation happens before any work: if any of sort/order/filters are invalid, return the corresponding `{:error, reason}` and do NOT return partial data.

On success:
- Sorting is deterministic: sort by the chosen field, using `:id` ascending as the tiebreak; `"desc"` reverses the ordering. String fields sort by default term (codepoint) order, so uppercase names sort before lowercase ones.
- `total_count` is the count AFTER filtering. `total_pages` is `ceil(total_count / page_size)`, or `0` when there are zero matching items.
- `meta` includes `:current_page`, `:page_size`, `:total_count`, `:total_pages`, `:sort` (atom), `:order` (atom), and `:filters` (a map with `:min_age`, `:max_age`, `:name_contains`, each `nil` when unset).
- Requesting a page beyond `total_pages` returns an empty `data` list but still-correct metadata (mirror the base endpoint's behavior here).

Use only the standard library. Give me the module in a single file.

## Additional interface contract

- `paginate/2`'s params argument is optional: `paginate(items)` must behave exactly like `paginate(items, %{})` (declare the second parameter with a `\\ %{}` default).

## The buggy module

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
    with {:error, sort} <- parse_sort(params),
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
      nil -> {:ok, nil}
      raw -> parse_integer(raw)
    end
  end

  # Only integers and integer-formatted strings are accepted; every other shape
  # (maps, lists, floats, booleans, partial numbers) is a bad request.
  defp parse_integer(value) when is_integer(value), do: {:ok, value}

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> {:ok, n}
      _ -> {:error, :invalid_filter}
    end
  end

  defp parse_integer(_value), do: {:error, :invalid_filter}

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
    case parse_paging_int(raw) do
      {:ok, n} when n >= 1 -> n
      _ -> @default_page
    end
  end

  defp parse_page(_), do: @default_page

  defp parse_page_size(%{"page_size" => raw}) do
    case parse_paging_int(raw) do
      {:ok, n} when n >= 1 -> min(n, @max_page_size)
      _ -> @default_page_size
    end
  end

  defp parse_page_size(_), do: @default_page_size

  # Paging inputs never fail the request: unparseable shapes fall back to the
  # caller's default, so this only reports success or `:error`.
  defp parse_paging_int(value) when is_integer(value), do: {:ok, value}

  defp parse_paging_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _rest} -> {:ok, n}
      :error -> :error
    end
  end

  defp parse_paging_int(_value), do: :error
end
```

## Failing test report

```
16 of 17 test(s) failed:

  * test defaults sort by id ascending with default paging
      
      
      match (=) failed
      code:  assert {:ok, %{data: data, meta: meta}} = QueryPaginator.paginate(items())
      left:  {:ok, %{data: data, meta: meta}}
      right: {:ok, :id}
      

  * test sorts by name ascending and descending with id tiebreak
      no match of right hand side value:
      
          {:ok, :name}
      

  * test sorts by age using id as tiebreak
      no match of right hand side value:
      
          {:ok, :age}
      

  * test rejects an invalid sort field
      
      
      match (=) failed
      code:  assert {:error, :invalid_sort_field} = QueryPaginator.paginate(items(), %{"sort" => "email"})
      left:  {:error, :invalid_sort_field}
      right: {:ok, %{data: [%{id: 1, name: "Alice", age: 30}, %{id: 2, name: "bob", age: 25}, %{id: 3, name: "Carol", age: 40}, %{id: 4, name: "dave", age: 25}, %{id: 5, name: "Eve", age: 35}, %{id: 6, name: "amanda", age: 22}], meta: %{sort: :invalid_sort_field, filters: %{min_age: nil, max_age: nil, name_contains: nil}, order: :asc, page_size: 2

  (…12 more)
```
