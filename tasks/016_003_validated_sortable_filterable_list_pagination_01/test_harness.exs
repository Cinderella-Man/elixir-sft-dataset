defmodule QueryPaginatorTest do
  use ExUnit.Case, async: false

  defp items do
    [
      %{id: 1, name: "Alice", age: 30},
      %{id: 2, name: "bob", age: 25},
      %{id: 3, name: "Carol", age: 40},
      %{id: 4, name: "dave", age: 25},
      %{id: 5, name: "Eve", age: 35},
      %{id: 6, name: "amanda", age: 22}
    ]
  end

  test "defaults sort by id ascending with default paging" do
    assert {:ok, %{data: data, meta: meta}} = QueryPaginator.paginate(items())
    assert Enum.map(data, & &1.id) == [1, 2, 3, 4, 5, 6]
    assert meta.current_page == 1
    assert meta.page_size == 20
    assert meta.total_count == 6
    assert meta.total_pages == 1
    assert meta.sort == :id
    assert meta.order == :asc
    assert meta.filters == %{min_age: nil, max_age: nil, name_contains: nil}
  end

  test "sorts by name ascending and descending with id tiebreak" do
    {:ok, %{data: asc}} = QueryPaginator.paginate(items(), %{"sort" => "name", "order" => "asc"})
    assert Enum.map(asc, & &1.name) == ["Alice", "Carol", "Eve", "amanda", "bob", "dave"]

    {:ok, %{data: desc}} =
      QueryPaginator.paginate(items(), %{"sort" => "name", "order" => "desc"})

    assert Enum.map(desc, & &1.name) ==
             Enum.reverse(["Alice", "Carol", "Eve", "amanda", "bob", "dave"])
  end

  test "sorts by age using id as tiebreak" do
    {:ok, %{data: data}} = QueryPaginator.paginate(items(), %{"sort" => "age", "order" => "asc"})
    assert Enum.map(data, & &1.id) == [6, 2, 4, 1, 5, 3]
  end

  test "rejects an invalid sort field" do
    assert {:error, :invalid_sort_field} = QueryPaginator.paginate(items(), %{"sort" => "email"})
  end

  test "rejects an invalid order" do
    assert {:error, :invalid_order} = QueryPaginator.paginate(items(), %{"order" => "sideways"})
  end

  test "min_age and max_age filters affect total_count and pages" do
    {:ok, %{data: data, meta: meta}} =
      QueryPaginator.paginate(items(), %{"min_age" => "25", "max_age" => "35", "page_size" => "2"})

    assert meta.total_count == 4
    assert meta.total_pages == 2
    assert length(data) == 2
    assert Enum.all?(data, &(&1.age >= 25 and &1.age <= 35))
  end

  test "name_contains is case-insensitive" do
    {:ok, %{data: data, meta: meta}} =
      QueryPaginator.paginate(items(), %{"name_contains" => "A"})

    names = Enum.map(data, & &1.name)
    assert "Alice" in names
    assert "Carol" in names
    assert "amanda" in names
    assert "dave" in names
    assert meta.total_count == length(data)
    assert meta.filters.name_contains == "A"
  end

  test "rejects a non-integer age filter" do
    assert {:error, :invalid_filter} = QueryPaginator.paginate(items(), %{"min_age" => "old"})
    assert {:error, :invalid_filter} = QueryPaginator.paginate(items(), %{"max_age" => "12x"})
  end

  test "clamps page_size and coerces bad page" do
    {:ok, %{meta: meta}} =
      QueryPaginator.paginate(items(), %{"page_size" => "500", "page" => "abc"})

    assert meta.page_size == 100
    assert meta.current_page == 1
  end

  test "page beyond total returns empty data with correct meta" do
    {:ok, %{data: data, meta: meta}} =
      QueryPaginator.paginate(items(), %{"page" => "99", "page_size" => "2"})

    assert data == []
    assert meta.current_page == 99
    assert meta.total_count == 6
    assert meta.total_pages == 3
  end

  test "empty items yields zero total_pages" do
    {:ok, %{data: data, meta: meta}} = QueryPaginator.paginate([])
    assert data == []
    assert meta.total_count == 0
    assert meta.total_pages == 0
  end
end
