# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule Catalog.Faceted do
  @allowed_sort ~w(name price id category)

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
