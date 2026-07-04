  test "malformed cursor is ignored and starts from the beginning" do
    %{data: data} = CursorPaginator.paginate(items(1..10), %{"limit" => "3", "cursor" => "!!!not-valid"})
    assert Enum.map(data, & &1.id) == [1, 2, 3]
  end