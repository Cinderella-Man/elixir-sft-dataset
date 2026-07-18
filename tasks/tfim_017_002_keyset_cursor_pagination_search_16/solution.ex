  test "integer limit above the maximum yields at most one hundred items" do
    many =
      for i <- 1..150 do
        %{id: i, name: "Item #{i}", category: "bulk", price_cents: i * 10}
      end

    assert {:ok, %{data: data, has_more: true, next_cursor: cursor}} =
             KeysetSearch.search(many, %{"sort" => "id", "limit" => 500})

    assert length(data) == 100
    assert List.last(ids(data)) == 100
    assert is_binary(cursor)
  end