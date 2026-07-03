defmodule EtsCatalogTest do
  use ExUnit.Case, async: false

  defp seed(table, range) do
    for i <- range, do: EtsCatalog.insert(table, %{id: i, name: "Item #{i}"})
    table
  end

  test "returns first page ordered by id ascending" do
    table = EtsCatalog.new() |> seed(1..25)

    %{data: data, meta: meta} = EtsCatalog.list(table, %{"page_size" => "10"})
    assert Enum.map(data, & &1.id) == Enum.to_list(1..10)
    assert meta.requested_page == 1
    assert meta.current_page == 1
    assert meta.page_size == 10
    assert meta.total_count == 25
    assert meta.total_pages == 3
  end

  test "later inserts overwrite same id and count reflects uniqueness" do
    table = EtsCatalog.new()
    EtsCatalog.insert(table, %{id: 1, name: "old"})
    EtsCatalog.insert(table, %{id: 1, name: "new"})

    assert EtsCatalog.count(table) == 1
    %{data: [item]} = EtsCatalog.list(table)
    assert item.name == "new"
  end

  test "clamps requested page beyond total to the last page and serves its items" do
    table = EtsCatalog.new() |> seed(1..5)

    %{data: data, meta: meta} = EtsCatalog.list(table, %{"page" => "99", "page_size" => "2"})
    assert Enum.map(data, & &1.id) == [5]
    assert meta.requested_page == 99
    assert meta.current_page == 3
    assert meta.total_pages == 3
    assert meta.total_count == 5
  end

  test "middle page returns the correct window" do
    table = EtsCatalog.new() |> seed(1..12)

    %{data: data, meta: meta} = EtsCatalog.list(table, %{"page" => "2", "page_size" => "5"})
    assert Enum.map(data, & &1.id) == [6, 7, 8, 9, 10]
    assert meta.current_page == 2
  end

  test "empty catalog yields empty data, page 1, zero total_pages" do
    table = EtsCatalog.new()

    %{data: data, meta: meta} = EtsCatalog.list(table)
    assert data == []
    assert meta.current_page == 1
    assert meta.total_count == 0
    assert meta.total_pages == 0
  end

  test "clamps page_size and coerces bad page values" do
    table = EtsCatalog.new() |> seed(1..150)

    %{meta: meta} = EtsCatalog.list(table, %{"page_size" => "500", "page" => "-3"})
    assert meta.page_size == 100
    assert meta.requested_page == 1
    assert meta.current_page == 1
    assert meta.total_pages == 2
  end

  test "concurrent inserts from many processes are all reflected" do
    table = EtsCatalog.new()

    1..200
    |> Task.async_stream(
      fn i -> EtsCatalog.insert(table, %{id: i, name: "Item #{i}"}) end,
      max_concurrency: 16,
      ordered: false
    )
    |> Enum.to_list()

    assert EtsCatalog.count(table) == 200

    %{data: data, meta: meta} = EtsCatalog.list(table, %{"page" => "2", "page_size" => "50"})
    assert meta.total_count == 200
    assert meta.total_pages == 4
    assert Enum.map(data, & &1.id) == Enum.to_list(51..100)
  end

  test "snapshot is internally coherent: data length never exceeds page_size" do
    table = EtsCatalog.new() |> seed(1..37)

    %{data: data, meta: meta} = EtsCatalog.list(table, %{"page" => "4", "page_size" => "10"})
    assert length(data) == 7
    assert meta.current_page == 4
    assert meta.total_pages == 4
  end
end