  test "valid? accepts an integer code" do
    assert HOTP.valid?(@secret, 287_082, 1) == {:ok, 2}
  end