  test "empty string returns :malformed" do
    assert {:error, :malformed} = open("", @key)
  end