  test "unparseable and blank price bounds are ignored rather than filtering everything out" do
    assert {:ok, %{data: data, has_more: false}} =
             KeysetSearch.search(products(), %{
               "min_price" => "abc",
               "max_price" => "  ",
               "sort" => "id",
               "limit" => "10"
             })

    assert ids(data) == [1, 2, 3, 4, 5, 6, 7, 8]
  end