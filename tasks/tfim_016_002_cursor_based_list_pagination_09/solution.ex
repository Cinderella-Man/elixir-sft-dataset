  test "empty item list yields empty data and nil cursors" do
    %{data: data, meta: meta} = CursorPaginator.paginate([])
    assert data == []
    assert meta.has_next == false
    assert meta.has_prev == false
    assert meta.next_cursor == nil
    assert meta.prev_cursor == nil
  end