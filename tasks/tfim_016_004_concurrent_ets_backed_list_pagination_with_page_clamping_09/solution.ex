  test "snapshot is internally coherent: data length never exceeds page_size" do
    table = EtsCatalog.new() |> seed(1..37)

    %{data: data, meta: meta} = EtsCatalog.list(table, %{"page" => "4", "page_size" => "10"})
    assert length(data) == 7
    assert meta.current_page == 4
    assert meta.total_pages == 4
  end