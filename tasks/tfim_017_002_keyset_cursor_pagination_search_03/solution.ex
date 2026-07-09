  test "cursor walks through all pages without overlap" do
    p = products()

    {:ok, %{data: d1, next_cursor: c1}} = KeysetSearch.search(p, %{"sort" => "price"})

    {:ok, %{data: d2, next_cursor: c2}} =
      KeysetSearch.search(p, %{"sort" => "price", "cursor" => c1})

    {:ok, %{data: d3, next_cursor: c3, has_more: more3}} =
      KeysetSearch.search(p, %{"sort" => "price", "cursor" => c2})

    assert ids(d1) == [5, 7, 3]
    assert ids(d2) == [6, 4, 1]
    assert ids(d3) == [2, 8]
    assert c3 == nil
    assert more3 == false
  end