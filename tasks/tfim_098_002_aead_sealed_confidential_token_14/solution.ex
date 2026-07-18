  test "truncated token returns :malformed" do
    token = seal("hello", @key, 60)
    truncated = binary_part(token, 0, div(byte_size(token), 4))
    assert {:error, :malformed} = open(truncated, @key)
  end