  test "backward navigation returns the preceding window in ascending order" do
    all = items(1..12)

    cursor = CursorPaginator.encode_cursor(10)
    page3 = CursorPaginator.paginate(all, %{"limit" => "5", "cursor" => cursor})
    assert Enum.map(page3.data, & &1.id) == [11, 12]

    prev =
      CursorPaginator.paginate(all, %{
        "limit" => "5",
        "direction" => "prev",
        "cursor" => page3.meta.prev_cursor
      })

    assert Enum.map(prev.data, & &1.id) == [6, 7, 8, 9, 10]
    assert prev.meta.has_prev == true
    assert prev.meta.has_next == true
  end