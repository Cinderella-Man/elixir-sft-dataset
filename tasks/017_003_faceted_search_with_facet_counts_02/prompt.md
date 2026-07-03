# Implement `search/2`

Implement the public `search/2` function — the single entry point of
`Catalog.Faceted`. It takes a list of `products` (in-memory product maps) and a
string-keyed `params` map, and returns either
`{:ok, %{data: [...], facets: %{categories: %{...}, tags: %{...}}, total: integer}}`
or `{:error, :invalid_sort_field}`.

Its job is to orchestrate the private helpers already defined in the module:

1. **Sort validation first.** If `invalid_sort?(params)` returns `true`, return
   `{:error, :invalid_sort_field}` immediately and do nothing else.

2. **Build the four filter predicates** as one-arity closures over `params`, one
   per filter dimension: name (`name_match?/2`), price (`price_match?/2`),
   category (`category_match?/2`), and tags (`tags_match?/2`).

3. **Compute the fully-filtered set** (`full`): the products for which *all four*
   predicates hold. `total` is `length(full)`.

4. **Compute the two facet source sets**, each excluding exactly one facet's own
   filter while keeping every other active filter:
   - the category-facet source excludes the category predicate (keeps name,
     price, tags);
   - the tag-facet source excludes the tags predicate (keeps name, price,
     category).

5. **Build the `facets` map** with `category_facets/1` over the category source
   and `tag_facets/1` over the tag source, under the keys `:categories` and
   `:tags`.

6. **Produce `data`** by sorting `full` with `sorter(params)` and mapping each
   product through `render/1`.

7. Return `{:ok, %{data: data, facets: facets, total: length(full)}}`.

The function has a default second argument (`params \\ %{}`) and a guard that both
`products` is a list and `params` is a map.

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
    # TODO
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