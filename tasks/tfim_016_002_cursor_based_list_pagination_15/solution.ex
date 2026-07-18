  test "encoded cursors contain only url-safe characters for varied ids" do
    for id <- [0, 1, -7, 42, 1_000_000, 9_007_199_254_740_993] do
      cursor = CursorPaginator.encode_cursor(id)
      assert cursor =~ ~r/\A[A-Za-z0-9_-]+\z/
      assert CursorPaginator.decode_cursor(cursor) == {:ok, id}
    end

    cursor = CursorPaginator.encode_cursor(123)
    refute cursor =~ "123"
  end