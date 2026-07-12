  test "valid? rejects a wrong code" do
    assert HOTP.valid?(@secret, "000000", 1) == :error
  end