  test "token is valid just before expiry" do
    token = seal("data", @key, 100)
    Clock.advance(99)
    assert {:ok, "data"} = open(token, @key)
  end