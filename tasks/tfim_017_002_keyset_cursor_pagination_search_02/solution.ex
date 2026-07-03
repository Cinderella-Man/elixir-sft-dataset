  test "first page sorts by price ascending with id tie-break" do
    assert {:ok, %{data: data, next_cursor: cursor, has_more: true}} =
             KeysetSearch.search(products(), %{"sort" => "price"})

    assert ids(data) == [5, 7, 3]
    assert is_binary(cursor)
  end