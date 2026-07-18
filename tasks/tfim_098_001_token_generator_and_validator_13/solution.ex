  test "truncated token returns :malformed" do
    token = generate("hello", "secret", 60)
    truncated = binary_part(token, 0, div(byte_size(token), 2))
    assert {:error, :malformed} = verify(truncated, "secret")
  end