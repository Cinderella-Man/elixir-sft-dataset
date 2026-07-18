  test "empty items yields zero total_pages" do
    {:ok, %{data: data, meta: meta}} = QueryPaginator.paginate([])
    assert data == []
    assert meta.total_count == 0
    assert meta.total_pages == 0
  end