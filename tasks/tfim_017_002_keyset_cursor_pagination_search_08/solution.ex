  test "limit is clamped to max and returns a single full page" do
    assert {:ok, %{data: data, next_cursor: nil, has_more: false}} =
             KeysetSearch.search(products(), %{"sort" => "id", "limit" => "1000"})

    assert length(data) == 8
  end