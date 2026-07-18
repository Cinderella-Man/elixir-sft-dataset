# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `invalid_sort?` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Task 17 — V3: Relevance-Ranked Full-Text Search

Write me a self-contained Elixir context module `Catalog.Ranked` that searches a product catalog by **free-text relevance**: it tokenizes a query, scores each product across weighted fields (name weighted higher than description), and orders results by that relevance score — replacing the base task's simple `ILIKE` substring filter with an actual ranking algorithm.

To keep the module dependency-free and autotestable it operates over an **in-memory list of product maps**. Each product is:

```elixir
%{id: 1, name: "Running Shoes", description: "Lightweight shoes for running and trail",
  category: "footwear", price_cents: 8999}
```

Prices are stored as **integer cents** (no floats, no Decimal).

## Public API

Implement `Catalog.Ranked.search(products, params)` returning:

- `{:ok, %{data: [...]}}`, or
- `{:error, :invalid_sort_field}`.

`params` is a string-keyed map. Each `data` item is `%{id, name, category, price, score}` where `price` is a two-decimal dollar string and `score` is the computed integer relevance score.

## Search & scoring

- **`"q"`** — the free-text query. Tokenize by downcasing and splitting on any run of non-alphanumeric characters (so `"Running, shoes!"` ⇒ `["running", "shoes"]`).
- Tokenize each product's `name` and `description` the same way.
- **Prefix matching**: a query token matches a document token when the document token **starts with** the query token (so `"run"` matches `"running"`, and `"work"` matches `"workouts"`).
- **Score** = for each query token, `3 × (number of name tokens it prefix-matches) + 1 × (number of description tokens it prefix-matches)`, summed over all query tokens. Name matches are weighted 3×; multiple matches accumulate.
- When `"q"` is present and non-empty, **only products with a score greater than 0 are returned** (it acts as the search filter). When `"q"` is absent or empty, all products pass with score `0`.

## Pre-filters (applied before scoring)

- **`"category"`** — exact match.
- **`"min_price"` / `"max_price"`** — inclusive integer-cent string bounds; unparseable/blank ignored.

## Sorting

- **`"sort"`** — allowlist of exactly `"relevance"`, `"name"`, `"price"`. Any other value ⇒ `{:error, :invalid_sort_field}`. Absent ⇒ defaults to `"relevance"`.
- **`"order"`** — `"asc"` or `"desc"`.
  - For `"relevance"`, the default direction is **descending** (highest score first); an explicit `"asc"` reverses it. Ties broken by `name` ascending, then `id` ascending.
  - For `"name"` / `"price"`, the default is ascending; ties broken by `id` ascending.

## Constraints

- Pure Elixir, standard library only. No Ecto/Decimal/Phoenix.
- Scoring, prefix matching, field weighting, and ordering all happen inside the module.

## The module with `invalid_sort?` missing

```elixir
defmodule Catalog.Ranked do
  @moduledoc """
  Relevance-ranked full-text search over an in-memory product catalog.

  `search/2` tokenizes a free-text query, scores each product across weighted
  fields (name weighted 3×, description 1×) using prefix matching, applies
  category and price pre-filters, and orders the results by the requested sort
  key. Prices are stored as integer cents and rendered as two-decimal dollar
  strings.
  """

  @allowed_sort ~w(relevance name price)

  @type product :: %{
          required(:id) => integer(),
          required(:name) => String.t(),
          required(:category) => String.t(),
          required(:price_cents) => integer(),
          optional(:description) => String.t()
        }

  @type result_item :: %{
          id: integer(),
          name: String.t(),
          category: String.t(),
          price: String.t(),
          score: non_neg_integer()
        }

  @doc """
  Searches `products` using the string-keyed `params` map.

  Returns `{:ok, %{data: [item]}}` where each item is
  `%{id, name, category, price, score}`, or `{:error, :invalid_sort_field}` when
  `"sort"` is not one of `"relevance"`, `"name"`, or `"price"`.
  """
  @spec search([product()], map()) ::
          {:ok, %{data: [result_item()]}} | {:error, :invalid_sort_field}
  def search(products, params \\ %{}) when is_list(products) and is_map(params) do
    if invalid_sort?(params) do
      {:error, :invalid_sort_field}
    else
      query = tokenize(Map.get(params, "q"))

      filtered =
        Enum.filter(products, fn p ->
          category_match?(p, params) and price_match?(p, params)
        end)

      scored = Enum.map(filtered, fn p -> {p, score(p, query)} end)

      scored =
        if query == [] do
          scored
        else
          Enum.filter(scored, fn {_p, s} -> s > 0 end)
        end

      sort = Map.get(params, "sort", "relevance")
      order = Map.get(params, "order")
      sorted = Enum.sort(scored, comparator(sort, order))

      {:ok, %{data: Enum.map(sorted, fn {p, s} -> render(p, s) end)}}
    end
  end

  # -- Sort validation ------------------------------------------------------

  defp invalid_sort?(%{"sort" => s}) do
    # TODO
  end

  # -- Tokenizing & scoring -------------------------------------------------

  defp tokenize(nil), do: []

  defp tokenize(str) when is_binary(str) do
    str
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
  end

  defp tokenize(_), do: []

  defp score(_p, []), do: 0

  defp score(p, query) do
    name_tokens = tokenize(p.name)
    desc_tokens = tokenize(Map.get(p, :description))

    Enum.reduce(query, 0, fn qt, acc ->
      acc + 3 * count_prefix(name_tokens, qt) + count_prefix(desc_tokens, qt)
    end)
  end

  defp count_prefix(tokens, qt) do
    Enum.count(tokens, fn t -> String.starts_with?(t, qt) end)
  end

  # -- Ordering -------------------------------------------------------------

  defp comparator("relevance", ord) do
    dir = if ord == "asc", do: :asc, else: :desc

    fn {pa, sa}, {pb, sb} ->
      cond do
        sa != sb -> if dir == :desc, do: sa > sb, else: sa < sb
        pa.name != pb.name -> pa.name < pb.name
        true -> pa.id <= pb.id
      end
    end
  end

  defp comparator("name", ord) do
    dir = if ord == "desc", do: :desc, else: :asc

    fn {pa, _}, {pb, _} ->
      cond do
        pa.name != pb.name -> if dir == :asc, do: pa.name < pb.name, else: pa.name > pb.name
        true -> pa.id <= pb.id
      end
    end
  end

  defp comparator("price", ord) do
    dir = if ord == "desc", do: :desc, else: :asc

    fn {pa, _}, {pb, _} ->
      cond do
        pa.price_cents != pb.price_cents ->
          ascending? = pa.price_cents < pb.price_cents
          if dir == :asc, do: ascending?, else: not ascending?

        true ->
          pa.id <= pb.id
      end
    end
  end

  # -- Filtering ------------------------------------------------------------

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

  # -- Rendering ------------------------------------------------------------

  defp render(p, s) do
    %{id: p.id, name: p.name, category: p.category, price: format_price(p.price_cents), score: s}
  end

  defp format_price(cents) do
    dollars = div(cents, 100)
    remainder = String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")
    "#{dollars}.#{remainder}"
  end
end
```

Give me only the complete implementation of `invalid_sort?` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
