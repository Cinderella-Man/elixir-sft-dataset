  test "limit with trailing non-numeric characters falls back to the default" do
    %{data: data, meta: meta} = CursorPaginator.paginate(items(1..30), %{"limit" => "12abc"})

    assert meta.page_size == 20
    assert length(data) == 20
  end