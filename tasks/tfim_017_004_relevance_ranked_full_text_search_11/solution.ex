  test "price range pre-filter is inclusive" do
    assert {:ok, %{data: data}} =
             Ranked.search(products(), %{"min_price" => "2999", "max_price" => "2999"})

    assert Enum.sort(ids(data)) == [3, 5]
  end