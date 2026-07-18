  test "filters that match nothing yield zero total_count and zero total_pages" do
    {:ok, %{data: data, meta: meta}} =
      QueryPaginator.paginate(items(), %{"min_age" => "999", "page_size" => "2"})

    assert data == []
    assert meta.total_count == 0
    assert meta.total_pages == 0
    assert meta.filters.min_age == 999
    assert meta.filters.max_age == nil
  end