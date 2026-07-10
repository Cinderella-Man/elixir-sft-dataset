  test "empty string returns :malformed" do
    assert {:error, :malformed} = verify("", "secret")
  end