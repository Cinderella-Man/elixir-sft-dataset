# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule Catalog.RankedTest do
  use ExUnit.Case, async: false

  alias Catalog.Ranked

  defp products do
    [
      %{
        id: 1,
        name: "Running Shoes",
        description: "Lightweight shoes for running and trail",
        category: "footwear",
        price_cents: 8999
      },
      %{
        id: 2,
        name: "Trail Runner Pro",
        description: "Durable running shoe for rugged trails",
        category: "footwear",
        price_cents: 12_999
      },
      %{
        id: 3,
        name: "Wireless Mouse",
        description: "Ergonomic mouse for office work",
        category: "electronics",
        price_cents: 2999
      },
      %{
        id: 4,
        name: "Keyboard Wrist Rest",
        description: "Comfort rest for keyboard users",
        category: "accessories",
        price_cents: 1500
      },
      %{
        id: 5,
        name: "Yoga Mat",
        description: "Non-slip mat for yoga and workouts",
        category: "fitness",
        price_cents: 2999
      }
    ]
  end

  defp ids(data), do: Enum.map(data, & &1.id)

  test "matches only scored products, ranked by relevance descending" do
    assert {:ok, %{data: data}} = Ranked.search(products(), %{"q" => "run"})

    # p1: name 'running' (3) + desc 'running' (1) = 4
    # p2: name 'runner' (3) + desc 'running' (1) = 4  -> tie broken by name asc
    assert ids(data) == [1, 2]
    assert Enum.map(data, & &1.score) == [4, 4]
  end

  test "name matches outrank description-only matches" do
    assert {:ok, %{data: data}} = Ranked.search(products(), %{"q" => "trail"})

    # p2: name 'trail' (3) + desc 'trails' (1) = 4 ; p1: desc 'trail' (1) = 1
    assert ids(data) == [2, 1]
    assert Enum.map(data, & &1.score) == [4, 1]
  end

  test "multiple query tokens accumulate score" do
    assert {:ok, %{data: data}} = Ranked.search(products(), %{"q" => "running shoe"})

    # p1: name running(3)+shoes(3)=6, desc running(1)+shoes(1)=2 -> 8
    # p2: name 0, desc running(1)+shoe(1)=2 -> 2
    assert ids(data) == [1, 2]
    assert Enum.map(data, & &1.score) == [8, 2]
  end

  test "prefix matching tolerates partial query tokens" do
    assert {:ok, %{data: data}} = Ranked.search(products(), %{"q" => "work"})

    # p3 desc 'work' (1); p5 desc 'workouts' via prefix (1) -> tie, name asc
    assert ids(data) == [3, 5]
    assert Enum.map(data, & &1.score) == [1, 1]
  end

  test "pre-filters apply before scoring" do
    assert {:ok, %{data: data}} =
             Ranked.search(products(), %{"q" => "run", "category" => "footwear"})

    assert Enum.sort(ids(data)) == [1, 2]

    assert {:ok, %{data: []}} =
             Ranked.search(products(), %{"q" => "run", "category" => "electronics"})
  end

  test "absent query returns all products with score 0, name-ordered" do
    assert {:ok, %{data: data}} = Ranked.search(products(), %{})

    assert ids(data) == [4, 1, 2, 3, 5]
    assert Enum.all?(data, &(&1.score == 0))
  end

  test "empty query string behaves like absent query" do
    assert {:ok, %{data: data}} = Ranked.search(products(), %{"q" => ""})
    assert length(data) == 5
  end

  test "sort override to price descending keeps only matches" do
    assert {:ok, %{data: data}} =
             Ranked.search(products(), %{"q" => "run", "sort" => "price", "order" => "desc"})

    assert ids(data) == [2, 1]
  end

  test "relevance ascending reverses the ranking" do
    assert {:ok, %{data: data}} =
             Ranked.search(products(), %{"q" => "trail", "order" => "asc"})

    assert ids(data) == [1, 2]
  end

  test "price range pre-filter is inclusive" do
    assert {:ok, %{data: data}} =
             Ranked.search(products(), %{"min_price" => "2999", "max_price" => "2999"})

    assert Enum.sort(ids(data)) == [3, 5]
  end

  test "invalid sort field returns error" do
    assert {:error, :invalid_sort_field} =
             Ranked.search(products(), %{"q" => "run", "sort" => "created_at"})
  end

  test "score is included and price is a two-decimal dollar string" do
    assert {:ok, %{data: [item | _]}} = Ranked.search(products(), %{"q" => "running shoe"})

    assert item.score == 8
    assert item.price == "89.99"
  end

  test "punctuated, capitalized query tokenizes into bare alphanumeric tokens" do
    assert {:ok, %{data: data}} = Ranked.search(products(), %{"q" => "Running, shoes!"})

    # tokens ["running", "shoes"]
    # p1: name running(3)+shoes(3)=6, desc running(1)+shoes(1)=2 -> 8
    # p2: name 0, desc running(1) only ("shoe" does not start with "shoes") -> 1
    assert ids(data) == [1, 2]
    assert Enum.map(data, & &1.score) == [8, 1]
  end

  test "a single query token accumulates once per matching document token" do
    assert {:ok, %{data: data}} = Ranked.search(products(), %{"q" => "r"})

    # p2: name runner(3) + desc running(1)+rugged(1) = 5
    # p4: name rest(3) + desc rest(1) = 4
    # p1: name running(3) + desc running(1) = 4  -> tie with p4, name asc
    assert ids(data) == [2, 4, 1]
    assert Enum.map(data, & &1.score) == [5, 4, 4]
  end

  test "unparseable and blank price bounds are ignored rather than excluding products" do
    # TODO
  end

  test "price sort defaults to ascending and breaks equal prices by id ascending" do
    assert {:ok, %{data: data}} = Ranked.search(products(), %{"sort" => "price"})

    # 1500(4), 2999(3), 2999(5) -> tie by id asc, 8999(1), 12999(2)
    assert ids(data) == [4, 3, 5, 1, 2]
  end

  test "explicit name sort with desc order reverses alphabetical ordering" do
    assert {:ok, %{data: data}} =
             Ranked.search(products(), %{"sort" => "name", "order" => "desc"})

    assert ids(data) == [5, 3, 2, 1, 4]
  end

  test "equal relevance scores with identical names fall back to id ascending" do
    catalog = [
      %{id: 7, name: "Alpha Kit", description: "kit", category: "c", price_cents: 100},
      %{id: 3, name: "Alpha Kit", description: "kit", category: "c", price_cents: 200},
      %{id: 9, name: "Alpha Box", description: "kit", category: "c", price_cents: 300}
    ]

    assert {:ok, %{data: data}} = Ranked.search(catalog, %{"q" => "alpha"})

    assert Enum.map(data, & &1.score) == [3, 3, 3]
    assert ids(data) == [9, 3, 7]
  end

  test "name sort with no order defaults to ascending alphabetical" do
    assert {:ok, %{data: data}} = Ranked.search(products(), %{"sort" => "name"})

    # Keyboard Wrist Rest(4), Running Shoes(1), Trail Runner Pro(2),
    # Wireless Mouse(3), Yoga Mat(5)
    assert ids(data) == [4, 1, 2, 3, 5]
  end

  test "explicit name sort asc orders alphabetically and breaks equal names by id ascending" do
    catalog = [
      %{id: 7, name: "Alpha Kit", description: "kit", category: "c", price_cents: 100},
      %{id: 3, name: "Alpha Kit", description: "kit", category: "c", price_cents: 200},
      %{id: 9, name: "Alpha Box", description: "kit", category: "c", price_cents: 300}
    ]

    assert {:ok, %{data: data}} =
             Ranked.search(catalog, %{"sort" => "name", "order" => "asc"})

    # Alpha Box(9) first, then the two Alpha Kit rows by id ascending
    assert ids(data) == [9, 3, 7]
  end
end
```
