  test "valid? resynchronizes forward within the look-ahead window" do
    # Code for counter 2, server stored counter 1, look-ahead of 2 covers 1..3.
    assert HOTP.valid?(@secret, "359152", 1, look_ahead: 2) == {:ok, 3}
  end