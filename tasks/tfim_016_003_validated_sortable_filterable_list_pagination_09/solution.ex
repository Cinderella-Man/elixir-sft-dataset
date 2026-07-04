  test "rejects a non-integer age filter" do
    assert {:error, :invalid_filter} = QueryPaginator.paginate(items(), %{"min_age" => "old"})
    assert {:error, :invalid_filter} = QueryPaginator.paginate(items(), %{"max_age" => "12x"})
  end