  test "empty catalog yields empty data, page 1, zero total_pages" do
    table = EtsCatalog.new()

    %{data: data, meta: meta} = EtsCatalog.list(table)
    assert data == []
    assert meta.current_page == 1
    assert meta.total_count == 0
    assert meta.total_pages == 0
  end