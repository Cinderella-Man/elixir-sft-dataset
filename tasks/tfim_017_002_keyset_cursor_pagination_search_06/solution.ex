  test "partial case-insensitive name search" do
    assert {:ok, %{data: data}} =
             KeysetSearch.search(products(), %{"name" => "shoe", "sort" => "id", "limit" => "10"})

    assert Enum.sort(ids(data)) == [1, 7, 8]
  end