  test "clamps page_size and coerces bad page" do
    {:ok, %{meta: meta}} =
      QueryPaginator.paginate(items(), %{"page_size" => "500", "page" => "abc"})

    assert meta.page_size == 100
    assert meta.current_page == 1
  end