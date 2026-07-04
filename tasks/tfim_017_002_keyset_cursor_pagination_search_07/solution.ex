  test "price range filtering is inclusive on cents" do
    assert {:ok, %{data: data}} =
             KeysetSearch.search(products(), %{
               "min_price" => "2999",
               "max_price" => "2999",
               "sort" => "id"
             })

    assert Enum.sort(ids(data)) == [3, 6]
  end