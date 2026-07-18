  test "a present-but-non-integer nested filter value is rejected, not raised" do
    assert {:error, :invalid_filter} =
             QueryPaginator.paginate(items(), %{"min_age" => %{"gt" => "20"}})

    assert {:error, :invalid_filter} =
             QueryPaginator.paginate(items(), %{"max_age" => ["40"]})
  end