  test "descending sort breaks ties by higher id first" do
    assert {:ok, %{data: data}} =
             KeysetSearch.search(products(), %{"sort" => "price", "order" => "desc"})

    assert ids(data) == [8, 2, 1]
  end