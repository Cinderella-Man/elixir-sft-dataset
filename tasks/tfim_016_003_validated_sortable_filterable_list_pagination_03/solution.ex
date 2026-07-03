  test "sorts by name ascending and descending with id tiebreak" do
    {:ok, %{data: asc}} = QueryPaginator.paginate(items(), %{"sort" => "name", "order" => "asc"})
    assert Enum.map(asc, & &1.name) == ["Alice", "Carol", "Eve", "amanda", "bob", "dave"]

    {:ok, %{data: desc}} = QueryPaginator.paginate(items(), %{"sort" => "name", "order" => "desc"})
    assert Enum.map(desc, & &1.name) == Enum.reverse(["Alice", "Carol", "Eve", "amanda", "bob", "dave"])
  end