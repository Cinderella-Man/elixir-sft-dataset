  test "authentication check takes precedence over expiry check" do
    token = seal("old", @key_a, 1)
    Clock.advance(200)
    # Expired, but the wrong key means authentication fails first.
    assert {:error, :invalid} = open(token, @key_b)
  end