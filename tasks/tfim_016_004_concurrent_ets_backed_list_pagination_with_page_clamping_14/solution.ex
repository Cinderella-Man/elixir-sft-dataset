  test "empty catalog with an out-of-range requested page still reports page one" do
    table = EtsCatalog.new()

    %{data: data, meta: meta} = EtsCatalog.list(table, %{"page" => "99", "page_size" => "5"})
    assert data == []
    assert meta.requested_page == 99
    assert meta.current_page == 1
    assert meta.total_count == 0
    assert meta.total_pages == 0
  end