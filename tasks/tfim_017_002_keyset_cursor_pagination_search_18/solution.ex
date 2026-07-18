  test "page after a cursor is unaffected by items removed before the cursor" do
    p = products()

    {:ok, %{data: d1, next_cursor: c1}} = KeysetSearch.search(p, %{"sort" => "price"})
    assert ids(d1) == [5, 7, 3]

    shrunk = Enum.reject(p, &(&1.id in [5, 7]))

    assert {:ok, %{data: d2}} = KeysetSearch.search(shrunk, %{"sort" => "price", "cursor" => c1})

    assert ids(d2) == [6, 4, 1]
  end