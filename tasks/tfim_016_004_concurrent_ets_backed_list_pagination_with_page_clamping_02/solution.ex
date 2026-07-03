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