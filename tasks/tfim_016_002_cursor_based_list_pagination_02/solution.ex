  test "default returns first window with default limit of 20" do
    %{data: data, meta: meta} = CursorPaginator.paginate(items(1..25))

    assert length(data) == 20
    assert Enum.map(data, & &1.id) == Enum.to_list(1..20)
    assert meta.page_size == 20
    assert meta.has_prev == false
    assert meta.has_next == true
    assert meta.prev_cursor == nil
    assert is_binary(meta.next_cursor)
  end