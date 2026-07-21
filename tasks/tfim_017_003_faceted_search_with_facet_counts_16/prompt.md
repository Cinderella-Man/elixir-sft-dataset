# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Catalog.Faceted do
  @moduledoc """
  Faceted search over an in-memory product catalog.

  Supports partial name matching, multi-value (OR) category filters,
  multi-tag (AND) filters, and inclusive integer-cent price bounds. Alongside
  the filtered, sorted results it returns **facet counts** so a UI can render
  drill-down filters without dead-ends: each facet is computed by excluding
  exactly its own filter while every other active filter still applies.
  """

  @type product :: %{
          id: integer(),
          name: String.t(),
          category: String.t(),
          price_cents: integer(),
          tags: [String.t()]
        }

  @type item :: %{
          id: integer(),
          name: String.t(),
          category: String.t(),
          price: String.t(),
          tags: [String.t()]
        }

  @type result :: %{
          data: [item()],
          facets: %{
            categories: %{optional(String.t()) => pos_integer()},
            tags: %{optional(String.t()) => pos_integer()}
          },
          total: non_neg_integer()
        }

  @allowed_sort ~w(name price id category)

  @doc """
  Runs a faceted search over `products` using the string-keyed `params` map.

  Returns `{:ok, %{data: [...], facets: %{...}, total: integer}}`, or
  `{:error, :invalid_sort_field}` when `"sort"` is not one of
  `"name"`, `"price"`, `"id"`, `"category"`.
  """
  @spec search([product()], map()) :: {:ok, result()} | {:error, :invalid_sort_field}
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

  # -- Sort validation ------------------------------------------------------

  defp invalid_sort?(%{"sort" => s}), do: s not in @allowed_sort
  defp invalid_sort?(_), do: false

  defp sorter(params) do
    field = Map.get(params, "sort", "id")
    ord = order(params)

    fn a, b ->
      ka = {sort_value(a, field), a.id}
      kb = {sort_value(b, field), b.id}

      case ord do
        :asc -> ka <= kb
        :desc -> ka >= kb
      end
    end
  end

  defp order(params) do
    case Map.get(params, "order") do
      "desc" -> :desc
      _ -> :asc
    end
  end

  defp sort_value(p, "name"), do: p.name
  defp sort_value(p, "price"), do: p.price_cents
  defp sort_value(p, "category"), do: p.category
  defp sort_value(p, "id"), do: p.id
  defp sort_value(p, _), do: p.id

  # -- Facets ---------------------------------------------------------------

  defp category_facets(products), do: Enum.frequencies_by(products, & &1.category)

  defp tag_facets(products) do
    Enum.reduce(products, %{}, fn p, acc ->
      Enum.reduce(p.tags, acc, fn t, a -> Map.update(a, t, 1, &(&1 + 1)) end)
    end)
  end

  # -- Filtering ------------------------------------------------------------

  defp name_match?(p, %{"name" => n}) when is_binary(n) and n != "" do
    String.contains?(String.downcase(p.name), String.downcase(n))
  end

  defp name_match?(_, _), do: true

  defp category_match?(p, %{"categories" => cats}) when is_list(cats) and cats != [] do
    p.category in cats
  end

  defp category_match?(_, _), do: true

  defp tags_match?(p, %{"tags" => tags}) when is_list(tags) and tags != [] do
    Enum.all?(tags, fn t -> t in p.tags end)
  end

  defp tags_match?(_, _), do: true

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

  # -- Rendering ------------------------------------------------------------

  defp render(p) do
    %{
      id: p.id,
      name: p.name,
      category: p.category,
      price: format_price(p.price_cents),
      tags: p.tags
    }
  end

  defp format_price(cents) do
    dollars = div(cents, 100)
    remainder = String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")
    "#{dollars}.#{remainder}"
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule Catalog.FacetedTest do
  use ExUnit.Case, async: false

  alias Catalog.Faceted

  defp products do
    [
      %{
        id: 1,
        name: "Running Shoes",
        category: "footwear",
        price_cents: 8999,
        tags: ["running", "outdoor"]
      },
      %{
        id: 2,
        name: "Leather Boots",
        category: "footwear",
        price_cents: 14_999,
        tags: ["formal", "outdoor"]
      },
      %{
        id: 3,
        name: "Wireless Mouse",
        category: "electronics",
        price_cents: 2999,
        tags: ["wireless", "office"]
      },
      %{
        id: 4,
        name: "Mechanical Keyboard",
        category: "electronics",
        price_cents: 7450,
        tags: ["wired", "office"]
      },
      %{
        id: 5,
        name: "USB-C Cable",
        category: "electronics",
        price_cents: 999,
        tags: ["wired", "office"]
      },
      %{
        id: 6,
        name: "Yoga Mat",
        category: "fitness",
        price_cents: 2999,
        tags: ["outdoor", "home"]
      }
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
             Faceted.search(products(), %{
               "min_price" => "2999",
               "max_price" => "2999",
               "sort" => "id"
             })

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

  test "absent sort param defaults to ordering by id ascending" do
    assert {:ok, %{data: data, total: 6}} = Faceted.search(products(), %{})
    assert ids(data) == [1, 2, 3, 4, 5, 6]
  end

  test "empty categories list imposes no category constraint" do
    assert {:ok, %{data: data, total: 6, facets: facets}} =
             Faceted.search(products(), %{"categories" => [], "sort" => "id"})

    assert ids(data) == [1, 2, 3, 4, 5, 6]
    assert facets.categories == %{"footwear" => 2, "electronics" => 3, "fitness" => 1}
  end

  test "empty tags list imposes no tag constraint" do
    # TODO
  end

  test "blank and unparseable price bounds are ignored" do
    assert {:ok, %{data: data, total: 6}} =
             Faceted.search(products(), %{"min_price" => "", "max_price" => "abc", "sort" => "id"})

    assert ids(data) == [1, 2, 3, 4, 5, 6]

    assert {:ok, %{data: only_min, total: 2}} =
             Faceted.search(products(), %{
               "min_price" => "8999",
               "max_price" => "  ",
               "sort" => "id"
             })

    assert ids(only_min) == [1, 2]
  end

  test "descending sort breaks ties by id descending" do
    assert {:ok, %{data: data}} =
             Faceted.search(products(), %{"sort" => "category", "order" => "desc"})

    assert ids(data) == [2, 1, 6, 5, 4, 3]

    assert {:ok, %{data: asc}} = Faceted.search(products(), %{"sort" => "category"})
    assert ids(asc) == [3, 4, 5, 6, 1, 2]
  end

  test "empty result from a category selection keeps the full category facet source" do
    assert {:ok, %{data: [], total: 0, facets: facets}} =
             Faceted.search(products(), %{"categories" => ["nonexistent"]})

    assert facets.categories == %{"footwear" => 2, "electronics" => 3, "fitness" => 1}
    assert facets.tags == %{}
  end

  test "rendered item exposes exactly id, name, category, price and tags" do
    assert {:ok, %{data: [item]}} = Faceted.search(products(), %{"name" => "wireless mouse"})

    assert item.id == 3
    assert item.name == "Wireless Mouse"
    assert item.category == "electronics"
    assert item.price == "29.99"
    assert item.tags == ["wireless", "office"]
    assert Enum.sort(Map.keys(item)) == [:category, :id, :name, :price, :tags]
  end

  test "every rendered item carries its own name and tags" do
    assert {:ok, %{data: data, total: 6}} = Faceted.search(products(), %{"sort" => "id"})

    assert Enum.map(data, & &1.name) == [
             "Running Shoes",
             "Leather Boots",
             "Wireless Mouse",
             "Mechanical Keyboard",
             "USB-C Cable",
             "Yoga Mat"
           ]

    assert Enum.map(data, & &1.tags) == [
             ["running", "outdoor"],
             ["formal", "outdoor"],
             ["wireless", "office"],
             ["wired", "office"],
             ["wired", "office"],
             ["outdoor", "home"]
           ]
  end
end
```
