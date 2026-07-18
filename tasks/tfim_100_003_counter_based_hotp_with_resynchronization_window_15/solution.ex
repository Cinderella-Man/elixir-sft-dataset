  test "valid? returns the counter after the matched one" do
    # Code for counter 3, stored counter 1, look-ahead 5 covers 1..6 -> match at 3.
    assert HOTP.valid?(@secret, "969429", 1, look_ahead: 5) == {:ok, 4}
  end