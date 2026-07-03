# Implement `score/2`

Implement the private `score/2` function for `Catalog.Ranked`. It computes the
integer relevance score of a single product `p` against a list of already-tokenized,
downcased query tokens `query`.

Behaviour:

- When `query` is empty, the score is `0` (no query means every product passes with a
  zero score).
- Otherwise, tokenize the product's `name` and its `description` using the module's
  `tokenize/1` helper. The `description` key is optional, so read it with
  `Map.get(p, :description)` (which yields `nil` when absent — `tokenize/1` turns that
  into `[]`).
- For each query token, count how many **name** tokens it prefix-matches and how many
  **description** tokens it prefix-matches, using the `count_prefix/2` helper (which
  relies on `String.starts_with?/2`). Weight name matches by `3` and description
  matches by `1`.
- Sum these weighted counts across every query token and return the total. Multiple
  matches within a field accumulate — a single query token can contribute more than
  one match per field.

Below is the whole module with the body of `score/2` replaced by `# TODO`. Fill it in.

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

  defp invalid_sort?(%{"sort" => s}), do: s not in @allowed_sort
  defp invalid_sort?(_), do: false

  # -- Tokenizing & scoring -------------------------------------------------

  defp tokenize(nil), do: []

  defp tokenize(str) when is_binary(str) do
    str
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
  end

  defp tokenize(_), do: []

  defp score(p, query) do
    # TODO
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