  test "clamps requested page beyond total to the last page and serves its items" do
    table = EtsCatalog.new() |> seed(1..5)

    %{data: data, meta: meta} = EtsCatalog.list(table, %{"page" => "99", "page_size" => "2"})
    assert Enum.map(data, & &1.id) == [5]
    assert meta.requested_page == 99
    assert meta.current_page == 3
    assert meta.total_pages == 3
    assert meta.total_count == 5
  end