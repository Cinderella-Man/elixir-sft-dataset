  test "page beyond total returns empty data with correct meta" do
    {:ok, %{data: data, meta: meta}} =
      QueryPaginator.paginate(items(), %{"page" => "99", "page_size" => "2"})

    assert data == []
    assert meta.current_page == 99
    assert meta.total_count == 6
    assert meta.total_pages == 3
  end