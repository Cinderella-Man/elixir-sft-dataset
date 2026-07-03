defmodule Catalog.FacetedTest do
  use ExUnit.Case, async: false

  alias Catalog.Faceted

  defp products do
    [
      %{id: 1, name: "Running Shoes", category: "footwear", price_cents: 8999, tags: ["running", "outdoor"]},
      %{id: 2, name: "Leather Boots", category: "footwear", price_cents: 14_999, tags: ["formal", "outdoor"]},
      %{id: 3, name: "Wireless Mouse", category: "electronics", price_cents: 2999, tags: ["wireless", "office"]},
      %{id: 4, name: "Mechanical Keyboard", category: "electronics", price_cents: 7450, tags: ["wired", "office"]},
      %{id: 5, name: "USB-C Cable", category: "electronics", price_cents: 999, tags: ["wired", "office"]},
      %{id: 6, name: "Yoga Mat", category: "fitness", price_cents: 2999, tags: ["outdoor", "home"]}
    ]
  end

  defp ids(data), do: Enum.map(data, & &1.id)

  test "no params returns everything with full facet counts" do
    assert {:ok, %{data: data, facets: facets, total: 6}} = Faceted.search(products())

    assert length(data) == 6
    assert facets.categories == %{"footwear" => 2, "electronics" => 3, "fitness" => 1}

    assert facets.tags == %{
             "running" => 1,
             "outdoor" => 3,
             "formal" => 1,
             "wireless" => 1,
             "office" => 3,
             "wired" => 2,
             "home" => 1
           }
  end

  test "multi-value categories filter is OR" do
    assert {:ok, %{data: data, total: 3}} =
             Faceted.search(products(), %{"categories" => ["footwear", "fitness"], "sort" => "id"})

    assert ids(data) == [1, 2, 6]
  end

  test "category facet ignores the category selection but tag facet reflects it" do
    assert {:ok, %{facets: facets}} =
             Faceted.search(products(), %{"categories" => ["footwear", "fitness"]})

    # category facet excludes its own filter -> counts over the full set
    assert facets.categories == %{"footwear" => 2, "electronics" => 3, "fitness" => 1}
    # tag facet still has the category filter applied -> only 1,2,6
    assert facets.tags == %{"outdoor" => 3, "running" => 1, "formal" => 1, "home" => 1}
  end

  test "tags filter is AND" do
    assert {:ok, %{data: data, total: 2}} =
             Faceted.search(products(), %{"tags" => ["wired", "office"], "sort" => "id"})

    assert ids(data) == [4, 5]
  end

  test "selecting a tag shrinks the category facet" do
    assert {:ok, %{data: data, total: 3, facets: facets}} =
             Faceted.search(products(), %{"tags" => ["office"], "sort" => "id"})

    assert ids(data) == [3, 4, 5]
    # category facet excludes categories filter but the tag filter still applies
    assert facets.categories == %{"electronics" => 3}
    # tag facet excludes the tag filter -> full tag counts
    assert facets.tags["office"] == 3
    assert facets.tags["outdoor"] == 3
  end

  test "category and tag filters combine" do
    assert {:ok, %{data: data, total: 3, facets: facets}} =
             Faceted.search(products(), %{
               "categories" => ["electronics"],
               "tags" => ["office"],
               "sort" => "price"
             })

    assert ids(data) == [5, 3, 4]
    assert facets.categories == %{"electronics" => 3}
    assert facets.tags == %{"office" => 3, "wired" => 2, "wireless" => 1}
  end

  test "name search composes with facets" do
    assert {:ok, %{data: data, total: 1}} =
             Faceted.search(products(), %{"name" => "keyboard"})

    assert ids(data) == [4]
  end

  test "price range filter is inclusive" do
    assert {:ok, %{data: data, total: 2}} =
             Faceted.search(products(), %{"min_price" => "2999", "max_price" => "2999", "sort" => "id"})

    assert ids(data) == [3, 6]
  end

  test "sort by category descending with id tie-break" do
    assert {:ok, %{data: data}} =
             Faceted.search(products(), %{"sort" => "category", "order" => "desc"})

    categories = Enum.map(data, & &1.category)
    assert categories == Enum.sort(categories, :desc)
  end

  test "invalid sort field returns error" do
    assert {:error, :invalid_sort_field} =
             Faceted.search(products(), %{"sort" => "inserted_at"})
  end

  test "empty result still reports facet source counts" do
    assert {:ok, %{data: [], total: 0, facets: facets}} =
             Faceted.search(products(), %{"name" => "nope_xyz"})

    assert facets.categories == %{}
    assert facets.tags == %{}
  end

  test "price is serialized as a two-decimal dollar string" do
    assert {:ok, %{data: [item]}} = Faceted.search(products(), %{"name" => "usb"})
    assert item.price == "9.99"
  end
end