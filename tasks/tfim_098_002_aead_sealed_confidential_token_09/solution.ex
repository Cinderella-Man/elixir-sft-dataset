  test "wrong key returns :invalid" do
    token = seal("payload", @key_a, 300)
    assert {:error, :invalid} = open(token, @key_b)
  end