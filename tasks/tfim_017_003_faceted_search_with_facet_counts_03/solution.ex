  test "multi-value categories filter is OR" do
    assert {:ok, %{data: data, total: 3}} =
             Faceted.search(products(), %{"categories" => ["footwear", "fitness"], "sort" => "id"})

    assert ids(data) == [1, 2, 6]
  end