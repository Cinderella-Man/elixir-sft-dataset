  test "window emptied by a cursor past the last id yields nil cursors and false booleans" do
    all = items(1..5)

    %{data: data, meta: meta} =
      CursorPaginator.paginate(all, %{
        "limit" => "3",
        "cursor" => CursorPaginator.encode_cursor(5)
      })

    assert data == []
    assert meta.next_cursor == nil
    assert meta.prev_cursor == nil
    assert meta.has_next == false
    assert meta.has_prev == false
  end