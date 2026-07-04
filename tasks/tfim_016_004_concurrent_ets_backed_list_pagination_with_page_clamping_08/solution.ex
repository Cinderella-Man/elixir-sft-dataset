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