  test "expired token returns :expired" do
    token = seal("data", @key, 100)
    Clock.advance(101)
    assert {:error, :expired} = open(token, @key)
  end