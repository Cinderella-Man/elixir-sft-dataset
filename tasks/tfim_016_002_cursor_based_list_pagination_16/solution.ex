  test "single-arity paginate matches the two-arity call with an empty params map" do
    all = Enum.shuffle(items(1..25))

    assert CursorPaginator.paginate(all) == CursorPaginator.paginate(all, %{})
    assert CursorPaginator.paginate([]) == CursorPaginator.paginate([], %{})
  end