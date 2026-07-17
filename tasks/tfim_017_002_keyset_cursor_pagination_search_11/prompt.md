# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Catalog.KeysetSearch do
  @moduledoc """
  Searches, filters, sorts, and paginates an in-memory product catalog using
  keyset (cursor) pagination.

  The module operates over a list of product maps of the shape

      %{id: 3, name: "Wireless Mouse", category: "electronics", price_cents: 2999}

  and never returns the whole result set: callers receive one page at a time
  plus an opaque cursor that encodes the last item of the page under the
  current ordering. Prices are handled as integer cents to preserve precision
  and are rendered as two-decimal dollar strings on the way out.
  """

  @allowed_sort ~w(name price id)
  @default_limit 3
  @max_limit 100

  @typedoc "A product record in the catalog."
  @type product :: %{
          required(:id) => integer(),
          required(:name) => String.t(),
          required(:category) => String.t(),
          required(:price_cents) => integer()
        }

  @typedoc "A single rendered item on a page."
  @type item :: %{
          id: integer(),
          name: String.t(),
          category: String.t(),
          price: String.t()
        }

  @typedoc "A successful page of results."
  @type page :: %{
          data: [item()],
          next_cursor: String.t() | nil,
          has_more: boolean()
        }

  @doc """
  Searches, filters, sorts, and paginates `products` according to `params`.

  `params` is a string-keyed map (like decoded query params) supporting
  `"name"`, `"category"`, `"min_price"`, `"max_price"`, `"sort"`, `"order"`,
  `"limit"`, and `"cursor"`.

  Returns `{:ok, page}` on success, `{:error, :invalid_sort_field}` when the
  requested sort field is not allowed, or `{:error, :invalid_cursor}` when the
  supplied cursor is malformed, carries a wrongly typed payload, or was
  produced under a different sort.
  """
  @spec search([product()], map()) ::
          {:ok, page()} | {:error, :invalid_sort_field | :invalid_cursor}
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

  # -- Sort validation ------------------------------------------------------

  defp validate_sort(%{"sort" => s}) when s not in @allowed_sort,
    do: {:error, :invalid_sort_field}

  defp validate_sort(_), do: :ok

  defp sort_field(params), do: Map.get(params, "sort", "id")

  defp order(params) do
    case Map.get(params, "order") do
      "desc" -> :desc
      _ -> :asc
    end
  end

  defp limit(params) do
    case Map.get(params, "limit") do
      nil ->
        @default_limit

      v when is_integer(v) ->
        clamp(v)

      v when is_binary(v) ->
        case Integer.parse(v) do
          {n, ""} -> clamp(n)
          _ -> @default_limit
        end

      _ ->
        @default_limit
    end
  end

  defp clamp(n) when n < 1, do: @default_limit
  defp clamp(n) when n > @max_limit, do: @max_limit
  defp clamp(n), do: n

  # -- Filtering ------------------------------------------------------------

  defp matches?(p, params) do
    name_match?(p, params) and category_match?(p, params) and price_match?(p, params)
  end

  defp name_match?(p, %{"name" => n}) when is_binary(n) and n != "" do
    String.contains?(String.downcase(p.name), String.downcase(n))
  end

  defp name_match?(_, _), do: true

  defp category_match?(p, %{"category" => c}) when is_binary(c) and c != "" do
    p.category == c
  end

  defp category_match?(_, _), do: true

  defp price_match?(p, params) do
    min_ok =
      case parse_price(Map.get(params, "min_price")) do
        {:ok, cents} -> p.price_cents >= cents
        :error -> true
      end

    max_ok =
      case parse_price(Map.get(params, "max_price")) do
        {:ok, cents} -> p.price_cents <= cents
        :error -> true
      end

    min_ok and max_ok
  end

  defp parse_price(nil), do: :error
  defp parse_price(v) when is_integer(v), do: {:ok, v}

  defp parse_price(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp parse_price(_), do: :error

  # -- Sorting / keys -------------------------------------------------------

  defp sorter(params) do
    ord = order(params)

    fn a, b ->
      compare_key(ord, key_of(a, params), key_of(b, params)) != :after
    end
  end

  defp key_of(p, params), do: {sort_value(p, sort_field(params)), p.id}

  defp sort_value(p, "name"), do: p.name
  defp sort_value(p, "price"), do: p.price_cents
  defp sort_value(p, "id"), do: p.id

  defp compare_key(:asc, {v1, id1}, {v2, id2}) do
    cond do
      v1 < v2 -> :before
      v1 > v2 -> :after
      id1 < id2 -> :before
      id1 > id2 -> :after
      true -> :eq
    end
  end

  defp compare_key(:desc, {v1, id1}, {v2, id2}) do
    cond do
      v1 > v2 -> :before
      v1 < v2 -> :after
      id1 > id2 -> :before
      id1 < id2 -> :after
      true -> :eq
    end
  end

  # -- Cursor ---------------------------------------------------------------

  defp encode_cursor(p, params) do
    {value, id} = key_of(p, params)

    {sort_field(params), value, id}
    |> :erlang.term_to_binary()
    |> Base.url_encode64(padding: false)
  end

  defp decode_cursor(params, field) do
    case Map.get(params, "cursor") do
      nil ->
        {:ok, nil}

      "" ->
        {:ok, nil}

      c when is_binary(c) ->
        with {:ok, bin} <- Base.url_decode64(c, padding: false),
             {:ok, {^field, value, id}} <- safe_to_term(bin),
             true <- valid_key?(field, value, id) do
          {:ok, {value, id}}
        else
          _ -> {:error, :invalid_cursor}
        end

      _ ->
        {:error, :invalid_cursor}
    end
  end

  # The decoded payload is untrusted: its value must have the exact type the
  # sort field produces, otherwise Erlang's cross-type term ordering would
  # silently slice the page instead of failing loudly.
  defp valid_key?("name", value, id), do: is_binary(value) and is_integer(id)
  defp valid_key?("price", value, id), do: is_integer(value) and is_integer(id)
  defp valid_key?("id", value, id), do: is_integer(value) and is_integer(id) and value == id
  defp valid_key?(_, _, _), do: false

  defp safe_to_term(bin) do
    {:ok, :erlang.binary_to_term(bin, [:safe])}
  rescue
    _ -> :error
  end

  # -- Rendering ------------------------------------------------------------

  defp render(p) do
    %{id: p.id, name: p.name, category: p.category, price: format_price(p.price_cents)}
  end

  defp format_price(cents) do
    "#{div(cents, 100)}.#{String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")}"
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule Catalog.KeysetSearchTest do
  use ExUnit.Case, async: false

  alias Catalog.KeysetSearch

  defp products do
    [
      %{id: 1, name: "Running Shoes", category: "footwear", price_cents: 8999},
      %{id: 2, name: "Leather Boots", category: "footwear", price_cents: 14_999},
      %{id: 3, name: "Wireless Mouse", category: "electronics", price_cents: 2999},
      %{id: 4, name: "Mechanical Keyboard", category: "electronics", price_cents: 7450},
      %{id: 5, name: "USB-C Cable", category: "electronics", price_cents: 999},
      %{id: 6, name: "Yoga Mat", category: "fitness", price_cents: 2999},
      %{id: 7, name: "Shoe Polish Kit", category: "accessories", price_cents: 1200},
      %{id: 8, name: "SNOWSHOE Set", category: "outdoors", price_cents: 19_999}
    ]
  end

  defp ids(data), do: Enum.map(data, & &1.id)

  test "first page sorts by price ascending with id tie-break" do
    assert {:ok, %{data: data, next_cursor: cursor, has_more: true}} =
             KeysetSearch.search(products(), %{"sort" => "price"})

    assert ids(data) == [5, 7, 3]
    assert is_binary(cursor)
  end

  test "cursor walks through all pages without overlap" do
    p = products()

    {:ok, %{data: d1, next_cursor: c1}} = KeysetSearch.search(p, %{"sort" => "price"})

    {:ok, %{data: d2, next_cursor: c2}} =
      KeysetSearch.search(p, %{"sort" => "price", "cursor" => c1})

    {:ok, %{data: d3, next_cursor: c3, has_more: more3}} =
      KeysetSearch.search(p, %{"sort" => "price", "cursor" => c2})

    assert ids(d1) == [5, 7, 3]
    assert ids(d2) == [6, 4, 1]
    assert ids(d3) == [2, 8]
    assert c3 == nil
    assert more3 == false
  end

  test "descending sort breaks ties by higher id first" do
    assert {:ok, %{data: data}} =
             KeysetSearch.search(products(), %{"sort" => "price", "order" => "desc"})

    assert ids(data) == [8, 2, 1]
  end

  test "filters apply before pagination" do
    assert {:ok, %{data: data, has_more: false}} =
             KeysetSearch.search(products(), %{
               "category" => "electronics",
               "sort" => "price"
             })

    assert ids(data) == [5, 3, 4]
  end

  test "partial case-insensitive name search" do
    assert {:ok, %{data: data}} =
             KeysetSearch.search(products(), %{"name" => "shoe", "sort" => "id", "limit" => "10"})

    assert Enum.sort(ids(data)) == [1, 7, 8]
  end

  test "price range filtering is inclusive on cents" do
    assert {:ok, %{data: data}} =
             KeysetSearch.search(products(), %{
               "min_price" => "2999",
               "max_price" => "2999",
               "sort" => "id"
             })

    assert Enum.sort(ids(data)) == [3, 6]
  end

  test "limit is clamped to max and returns a single full page" do
    assert {:ok, %{data: data, next_cursor: nil, has_more: false}} =
             KeysetSearch.search(products(), %{"sort" => "id", "limit" => "1000"})

    assert length(data) == 8
  end

  test "invalid sort field returns error" do
    assert {:error, :invalid_sort_field} =
             KeysetSearch.search(products(), %{"sort" => "inserted_at"})
  end

  test "malformed cursor returns invalid_cursor" do
    assert {:error, :invalid_cursor} =
             KeysetSearch.search(products(), %{"sort" => "price", "cursor" => "!!!not-base64!!!"})
  end

  test "cursor built for one sort is rejected under another sort" do
    # TODO
  end

  test "empty result set yields nil cursor and no more" do
    assert {:ok, %{data: [], next_cursor: nil, has_more: false}} =
             KeysetSearch.search(products(), %{"name" => "nonexistent_xyz"})
  end

  test "price is serialized as a two-decimal dollar string" do
    assert {:ok, %{data: [item]}} =
             KeysetSearch.search(products(), %{"category" => "outdoors", "sort" => "id"})

    assert item.price == "199.99"
  end

  test "cursor carrying a wrongly typed payload is rejected instead of silently slicing" do
    forged =
      {"price", "not-a-price", 5}
      |> :erlang.term_to_binary()
      |> Base.url_encode64(padding: false)

    assert {:error, :invalid_cursor} =
             KeysetSearch.search(products(), %{"sort" => "price", "cursor" => forged})
  end

  test "non-positive and garbage limits fall back to the default page size" do
    for bad <- ["0", "-5", "abc", ""] do
      assert {:ok, %{data: data, has_more: true}} =
               KeysetSearch.search(products(), %{"sort" => "id", "limit" => bad})

      assert ids(data) == [1, 2, 3]
    end
  end

  test "integer limit above the maximum yields at most one hundred items" do
    many =
      for i <- 1..150 do
        %{id: i, name: "Item #{i}", category: "bulk", price_cents: i * 10}
      end

    assert {:ok, %{data: data, has_more: true, next_cursor: cursor}} =
             KeysetSearch.search(many, %{"sort" => "id", "limit" => 500})

    assert length(data) == 100
    assert List.last(ids(data)) == 100
    assert is_binary(cursor)
  end

  test "unparseable and blank price bounds are ignored rather than filtering everything out" do
    assert {:ok, %{data: data, has_more: false}} =
             KeysetSearch.search(products(), %{
               "min_price" => "abc",
               "max_price" => "  ",
               "sort" => "id",
               "limit" => "10"
             })

    assert ids(data) == [1, 2, 3, 4, 5, 6, 7, 8]
  end

  test "page after a cursor is unaffected by items removed before the cursor" do
    p = products()

    {:ok, %{data: d1, next_cursor: c1}} = KeysetSearch.search(p, %{"sort" => "price"})
    assert ids(d1) == [5, 7, 3]

    shrunk = Enum.reject(p, &(&1.id in [5, 7]))

    assert {:ok, %{data: d2}} = KeysetSearch.search(shrunk, %{"sort" => "price", "cursor" => c1})

    assert ids(d2) == [6, 4, 1]
  end
end
```
