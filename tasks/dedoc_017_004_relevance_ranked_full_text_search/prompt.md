# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule Catalog.Ranked do
  @allowed_sort ~w(relevance name price)

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
