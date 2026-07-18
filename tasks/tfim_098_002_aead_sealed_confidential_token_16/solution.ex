  test "non-binary token returns :malformed" do
    assert {:error, :malformed} = open(12345, @key)
  end