  test "valid? accepts the exact code and returns the next counter" do
    assert HOTP.valid?(@secret, "287082", 1) == {:ok, 2}
  end