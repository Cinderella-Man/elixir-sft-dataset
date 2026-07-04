  test "clamps limit to 100" do
    %{data: data, meta: meta} = CursorPaginator.paginate(items(1..150), %{"limit" => "500"})
    assert length(data) == 100
    assert meta.page_size == 100
  end