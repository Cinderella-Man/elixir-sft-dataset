  test "supports integer payload" do
    token = seal(12345, @key, 60)
    assert {:ok, 12345} = open(token, @key)
  end