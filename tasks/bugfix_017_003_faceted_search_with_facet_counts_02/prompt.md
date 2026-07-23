# One bug. Find it. Fix it.

The module below implements the task that follows, except for a single
behavior bug. The bottom of this prompt shows the real failure report from
its (hidden) test suite. Deliver the full corrected module: smallest
possible change, no restructuring, nothing else touched.

## Target behavior

# Task 17 — V2: Faceted Search with Multi-Value Filters and Facet Counts

Write me a self-contained Elixir context module `Catalog.Faceted` that implements **faceted search** over a product catalog: multi-value (OR) category filters, multi-tag (AND) filters, and — the defining feature — **facet counts** returned alongside the results so a UI can render "drill-down" filters without dead-ends.

To keep the module dependency-free and autotestable it operates over an **in-memory list of product maps**. Each product is:

```elixir
%{id: 3, name: "Wireless Mouse", category: "electronics", price_cents: 2999, tags: ["wireless", "office"]}
```

Prices are stored as **integer cents** (no floats, no Decimal).

## Public API

Implement `Catalog.Faceted.search(products, params)` returning:

- `{:ok, %{data: [...], facets: %{categories: %{...}, tags: %{...}}, total: integer}}`, or
- `{:error, :invalid_sort_field}`.

`params` is a string-keyed map.

## Filtering

- **`"name"`** — partial, case-insensitive substring match on the name.
- **`"categories"`** — a **list** of category strings; a product matches if its category is **any** of them (OR). Absent/empty list ⇒ no category constraint.
- **`"tags"`** — a **list** of tag strings; a product matches only if it contains **all** of them (AND). Absent/empty list ⇒ no tag constraint.
- **`"min_price"` / `"max_price"`** — inclusive integer-cent string bounds; unparseable/blank values are ignored.

`total` is the count of products passing **all** filters, and `data` is that same fully-filtered set (sorted).

## Facet counts (the key semantics)

Each facet reports how many products **would** match if the caller added values to *that* facet, so a facet's own selection must **not** constrain its own counts, while **every other** active filter still applies:

- **`facets.categories`** — a map of `category => count` computed over products passing every filter **except** the `"categories"` filter.
- **`facets.tags`** — a map of `tag => count` (each product contributes to one entry per tag it carries) computed over products passing every filter **except** the `"tags"` filter.

So selecting a category must not zero-out the other categories in `facets.categories` (the user can still widen the OR), but selecting a tag *does* shrink `facets.categories`, because the tag filter is a "different" filter that still applies. Facets never include entries with a zero count.

## Sorting

- **`"sort"`** — allowlist of exactly `"name"`, `"price"`, `"id"`, `"category"`. Any other value ⇒ `{:error, :invalid_sort_field}`. Absent ⇒ defaults to `"id"`.
- **`"order"`** — `"asc"` (default) or `"desc"`; ties broken by `id` in the same direction.

## Response format

Each item in `data` is `%{id, name, category, price, tags}` where `price` is a two-decimal dollar string. An empty result returns `data: []`, `total: 0`, and facets reflecting the remaining source sets.

## Constraints

- Pure Elixir, standard library only. No Ecto/Decimal/Phoenix.
- Facet counts must be computed by excluding exactly the corresponding facet's own filter and no other.

## Additional interface contract

- `search/2`'s params argument is optional: `search(products)` must behave exactly like `search(products, %{})` (declare the second parameter with a `\\ %{}` default).

## The buggy module

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
  defp invalid_sort?(_), do: true

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

## Failing test report

```
5 of 12 test(s) failed:

  * test no params returns everything with full facet counts
      
      
      match (=) failed
      code:  assert {:ok, %{data: data, facets: facets, total: 6}} = Faceted.search(products())
      left:  {:ok, %{data: data, facets: facets, total: 6}}
      right: {:error, :invalid_sort_field}
      

  * test category facet ignores the category selection but tag facet reflects it
      
      
      match (=) failed
      code:  assert {:ok, %{facets: facets}} = Faceted.search(products(), %{"categories" => ["footwear", "fitness"]})
      left:  {:ok, %{facets: facets}}
      right: {:error, :invalid_sort_field}
      

  * test name search composes with facets
      
      
      match (=) failed
      code:  assert {:ok, %{data: data, total: 1}} = Faceted.search(products(), %{"name" => "keyboard"})
      left:  {:ok, %{data: data, total: 1}}
      right: {:error, :invalid_sort_field}
      

  * test empty result still reports facet source counts
      
      
      match (=) failed
      code:  assert {:ok, %{data: [], total: 0, facets: facets}} = Faceted.search(products(), %{"name" => "nope_xyz"})
      left:  {:ok, %{data: [], total: 0, facets: facets}}
      right: {:error, :invalid_sort_field}
      

  (…1 more)
```
