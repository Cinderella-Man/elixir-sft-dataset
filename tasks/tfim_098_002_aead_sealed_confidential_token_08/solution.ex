  test "token expires exactly at ttl boundary" do
    token = seal("data", @key, 50)
    Clock.advance(50)
    assert {:error, :expired} = open(token, @key)
  end