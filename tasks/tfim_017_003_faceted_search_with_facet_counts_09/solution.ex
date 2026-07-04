  test "price range filter is inclusive" do
    assert {:ok, %{data: data, total: 2}} =
             Faceted.search(products(), %{"min_price" => "2999", "max_price" => "2999", "sort" => "id"})

    assert ids(data) == [3, 6]
  end