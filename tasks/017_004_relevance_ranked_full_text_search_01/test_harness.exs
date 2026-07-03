defmodule Catalog.RankedTest do
  use ExUnit.Case, async: false

  alias Catalog.Ranked

  defp products do
    [
      %{id: 1, name: "Running Shoes", description: "Lightweight shoes for running and trail", category: "footwear", price_cents: 8999},
      %{id: 2, name: "Trail Runner Pro", description: "Durable running shoe for rugged trails", category: "footwear", price_cents: 12_999},
      %{id: 3, name: "Wireless Mouse", description: "Ergonomic mouse for office work", category: "electronics", price_cents: 2999},
      %{id: 4, name: "Keyboard Wrist Rest", description: "Comfort rest for keyboard users", category: "accessories", price_cents: 1500},
      %{id: 5, name: "Yoga Mat", description: "Non-slip mat for yoga and workouts", category: "fitness", price_cents: 2999}
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
end