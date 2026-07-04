  test "rejects an invalid order" do
    assert {:error, :invalid_order} = QueryPaginator.paginate(items(), %{"order" => "sideways"})
  end