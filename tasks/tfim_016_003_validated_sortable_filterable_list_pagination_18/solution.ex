  test "paginate/1 returns exactly what paginate/2 with an empty map returns" do
    assert QueryPaginator.paginate(items()) == QueryPaginator.paginate(items(), %{})
    assert QueryPaginator.paginate([]) == QueryPaginator.paginate([], %{})
  end