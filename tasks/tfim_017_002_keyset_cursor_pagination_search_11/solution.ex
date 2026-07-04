  test "cursor built for one sort is rejected under another sort" do
    {:ok, %{next_cursor: cursor}} = KeysetSearch.search(products(), %{"sort" => "price"})

    assert {:error, :invalid_cursor} =
             KeysetSearch.search(products(), %{"sort" => "name", "cursor" => cursor})
  end