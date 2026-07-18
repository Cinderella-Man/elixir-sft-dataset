  test "page_size below one or non-numeric falls back to the default of 20" do
    {:ok, %{meta: zero}} = QueryPaginator.paginate(items(), %{"page_size" => "0"})
    assert zero.page_size == 20

    {:ok, %{meta: negative}} = QueryPaginator.paginate(items(), %{"page_size" => "-5"})
    assert negative.page_size == 20

    {:ok, %{data: data, meta: junk}} = QueryPaginator.paginate(items(), %{"page_size" => "many"})
    assert junk.page_size == 20
    assert junk.total_pages == 1
    assert length(data) == 6
  end