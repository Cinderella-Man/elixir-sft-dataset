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
    assert {:ok, %{data: data}} =
             Ranked.search(products(), %{"min_price" => "abc", "max_price" => "   "})

    assert Enum.sort(ids(data)) == [1, 2, 3, 4, 5]

    assert {:ok, %{data: partial}} =
             Ranked.search(products(), %{"min_price" => "2999abc", "max_price" => ""})

    assert Enum.sort(ids(partial)) == [1, 2, 3, 4, 5]
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
