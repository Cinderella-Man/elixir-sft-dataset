  test "cursor encode/decode round trips and rejects garbage" do
    encoded = CursorPaginator.encode_cursor(42)
    assert is_binary(encoded)
    assert CursorPaginator.decode_cursor(encoded) == {:ok, 42}
    assert CursorPaginator.decode_cursor("garbage***") == :error
    assert CursorPaginator.decode_cursor(123) == :error
  end