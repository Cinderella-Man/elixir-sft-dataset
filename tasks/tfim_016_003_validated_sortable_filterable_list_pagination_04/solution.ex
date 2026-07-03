  test "sorts by age using id as tiebreak" do
    {:ok, %{data: data}} = QueryPaginator.paginate(items(), %{"sort" => "age", "order" => "asc"})
    assert Enum.map(data, & &1.id) == [6, 2, 4, 1, 5, 3]
  end