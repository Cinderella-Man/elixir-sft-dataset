# Implement to green

Treat the ExUnit suite below as the full requirements document. Write the
code under test so the whole suite passes. Dependencies: only what the
tests already use (the standard library and OTP otherwise). Style:
`@moduledoc`, `@doc` + `@spec` on the public API, warning-free compile.

## The test suite

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
    {:ok, %{next_cursor: cursor}} = KeysetSearch.search(products(), %{"sort" => "price"})

    assert {:error, :invalid_cursor} =
             KeysetSearch.search(products(), %{"sort" => "name", "cursor" => cursor})
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

  # A catalog whose name ordering differs from both its id ordering and its
  # price ordering, with a duplicated name so the id tie-break is observable.
  defp named_products do
    [
      %{id: 30, name: "Anvil", category: "tools", price_cents: 500},
      %{id: 10, name: "Zephyr Fan", category: "home", price_cents: 100},
      %{id: 20, name: "Mallet", category: "tools", price_cents: 300},
      %{id: 5, name: "Mallet", category: "tools", price_cents: 900}
    ]
  end

  test "sorting by name returns rows ordered by name with id tie-break" do
    assert {:ok, %{data: data, has_more: false, next_cursor: nil}} =
             KeysetSearch.search(named_products(), %{"sort" => "name", "limit" => "10"})

    assert ids(data) == [30, 5, 20, 10]
  end

  test "name-sorted cursor resumes strictly after the last name on the page" do
    p = named_products()

    assert {:ok, %{data: d1, next_cursor: c1, has_more: true}} =
             KeysetSearch.search(p, %{"sort" => "name", "limit" => "2"})

    assert ids(d1) == [30, 5]
    assert is_binary(c1)

    assert {:ok, %{data: d2, next_cursor: nil, has_more: false}} =
             KeysetSearch.search(p, %{"sort" => "name", "limit" => "2", "cursor" => c1})

    assert ids(d2) == [20, 10]
  end

  test "name-sorted results descend when order is desc" do
    assert {:ok, %{data: data}} =
             KeysetSearch.search(named_products(), %{
               "sort" => "name",
               "order" => "desc",
               "limit" => "10"
             })

    assert ids(data) == [10, 20, 5, 30]
  end

  test "absent sort defaults to ordering by id" do
    assert {:ok, %{data: data, has_more: false}} =
             KeysetSearch.search(products(), %{"limit" => "10"})

    assert ids(data) == [1, 2, 3, 4, 5, 6, 7, 8]
  end

  test "absent sort defaults to id even when name and price orderings differ" do
    assert {:ok, %{data: data, has_more: true}} =
             KeysetSearch.search(named_products(), %{"limit" => "2"})

    assert ids(data) == [5, 10]
  end
end
```

Deliverable: the module(s) alone in a single file — not the tests.
