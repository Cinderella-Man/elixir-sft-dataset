  test "non-numeric and sub-1 limits fall back to default" do
    %{meta: m1} = CursorPaginator.paginate(items(1..3), %{"limit" => "abc"})
    assert m1.page_size == 20

    %{meta: m2} = CursorPaginator.paginate(items(1..3), %{"limit" => "0"})
    assert m2.page_size == 20

    %{meta: m3} = CursorPaginator.paginate(items(1..3), %{"limit" => "-4"})
    assert m3.page_size == 20
  end