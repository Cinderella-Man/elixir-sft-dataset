  test "valid? rejects a code beyond the look-ahead window" do
    # Code for counter 4, server at counter 1, look-ahead 2 covers only 1..3.
    assert HOTP.valid?(@secret, "338314", 1, look_ahead: 2) == :error
  end