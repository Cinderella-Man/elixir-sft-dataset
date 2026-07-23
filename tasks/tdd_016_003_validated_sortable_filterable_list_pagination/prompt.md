# The tests are the spec

Below is a complete, self-contained ExUnit suite. It is the only
specification you get: build the module (or modules) it exercises until
every test passes. Reach for nothing beyond what the tests themselves
require — the standard library and OTP unless the suite says otherwise.
House style applies (`@moduledoc`, `@doc` + `@spec` on the public API,
no compiler warnings).

## The test suite

```elixir
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

  test "descending order reverses the whole ordering so tied items list ids descending" do
    {:ok, %{data: by_age}} =
      QueryPaginator.paginate(items(), %{"sort" => "age", "order" => "desc"})

    assert Enum.map(by_age, & &1.age) == [40, 35, 30, 25, 25, 22]
    assert Enum.map(by_age, & &1.id) == [3, 5, 1, 4, 2, 6]

    same_name = [
      %{id: 7, name: "zed", age: 50},
      %{id: 8, name: "zed", age: 51},
      %{id: 9, name: "abe", age: 52}
    ]

    {:ok, %{data: by_name}} =
      QueryPaginator.paginate(same_name, %{"sort" => "name", "order" => "desc"})

    assert Enum.map(by_name, & &1.name) == ["zed", "zed", "abe"]
    assert Enum.map(by_name, & &1.id) == [8, 7, 9]
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

  test "a present-but-non-integer nested filter value is rejected, not raised" do
    assert {:error, :invalid_filter} =
             QueryPaginator.paginate(items(), %{"min_age" => %{"gt" => "20"}})

    assert {:error, :invalid_filter} =
             QueryPaginator.paginate(items(), %{"max_age" => ["40"]})
  end

  test "page_size below one or non-numeric falls back to the default of 20" do
    {:ok, %{meta: zero}} = QueryPaginator.paginate(items(), %{"page_size" => "0"})
    assert zero.page_size == 20

    {:ok, %{meta: negative}} = QueryPaginator.paginate(items(), %{"page_size" => "-5"})
    assert negative.page_size == 20

    {:ok, %{data: data, meta: junk}} = QueryPaginator.paginate(items(), %{"page_size" => "many"})
    assert junk.page_size == 20
    assert junk.total_pages == 1
    assert length(data) == 6
  end

  test "page below one falls back to the first page" do
    {:ok, %{data: zero_data, meta: zero}} =
      QueryPaginator.paginate(items(), %{"page" => "0", "page_size" => "2"})

    assert zero.current_page == 1
    assert Enum.map(zero_data, & &1.id) == [1, 2]

    {:ok, %{data: neg_data, meta: negative}} =
      QueryPaginator.paginate(items(), %{"page" => "-4", "page_size" => "2"})

    assert negative.current_page == 1
    assert Enum.map(neg_data, & &1.id) == [1, 2]
  end

  test "filters that match nothing yield zero total_count and zero total_pages" do
    {:ok, %{data: data, meta: meta}} =
      QueryPaginator.paginate(items(), %{"min_age" => "999", "page_size" => "2"})

    assert data == []
    assert meta.total_count == 0
    assert meta.total_pages == 0
    assert meta.filters.min_age == 999
    assert meta.filters.max_age == nil
  end

  test "min_age and max_age are inclusive at exactly-equal boundary values" do
    {:ok, %{data: data, meta: meta}} =
      QueryPaginator.paginate(items(), %{"min_age" => "25", "max_age" => "25"})

    assert Enum.map(data, & &1.id) == [2, 4]
    assert meta.total_count == 2
    assert meta.total_pages == 1

    {:ok, %{data: single}} =
      QueryPaginator.paginate(items(), %{"min_age" => "22", "max_age" => "22"})

    assert Enum.map(single, & &1.id) == [6]
  end

  test "paginate/1 returns exactly what paginate/2 with an empty map returns" do
    assert QueryPaginator.paginate(items()) == QueryPaginator.paginate(items(), %{})
    assert QueryPaginator.paginate([]) == QueryPaginator.paginate([], %{})
  end
end
```

Send back the implementation only — one file, no tests.
