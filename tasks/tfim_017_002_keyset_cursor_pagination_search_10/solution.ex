  test "malformed cursor returns invalid_cursor" do
    assert {:error, :invalid_cursor} =
             KeysetSearch.search(products(), %{"sort" => "price", "cursor" => "!!!not-base64!!!"})
  end