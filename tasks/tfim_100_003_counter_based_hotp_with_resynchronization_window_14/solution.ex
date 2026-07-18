  test "valid? is forward-only and never checks counters below the stored one" do
    # "755224" is the code for counter 0, but the server is at counter 1;
    # even a generous look-ahead only scans forward.
    assert HOTP.valid?(@secret, "755224", 1, look_ahead: 5) == :error
  end