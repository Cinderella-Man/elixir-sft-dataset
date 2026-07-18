  test "empty result set yields nil cursor and no more" do
    assert {:ok, %{data: [], next_cursor: nil, has_more: false}} =
             KeysetSearch.search(products(), %{"name" => "nonexistent_xyz"})
  end