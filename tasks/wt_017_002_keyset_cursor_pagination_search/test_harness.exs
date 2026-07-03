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
    {:ok, %{data: d2, next_cursor: c2}} = KeysetSearch.search(p, %{"sort" => "price", "cursor" => c1})

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
end