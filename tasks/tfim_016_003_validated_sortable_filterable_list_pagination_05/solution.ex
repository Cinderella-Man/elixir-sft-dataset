  test "rejects an invalid sort field" do
    assert {:error, :invalid_sort_field} = QueryPaginator.paginate(items(), %{"sort" => "email"})
  end