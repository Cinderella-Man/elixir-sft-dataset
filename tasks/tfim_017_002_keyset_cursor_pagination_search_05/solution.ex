  test "filters apply before pagination" do
    assert {:ok, %{data: data, has_more: false}} =
             KeysetSearch.search(products(), %{
               "category" => "electronics",
               "sort" => "price"
             })

    assert ids(data) == [5, 3, 4]
  end