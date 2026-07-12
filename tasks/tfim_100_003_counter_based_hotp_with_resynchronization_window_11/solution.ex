  test "valid? with default look_ahead does not accept a future counter's code" do
    # "359152" is the code for counter 2, but we are at counter 1 with no look-ahead.
    assert HOTP.valid?(@secret, "359152", 1) == :error
  end