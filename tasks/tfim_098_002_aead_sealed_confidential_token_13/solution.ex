  test "random binary returns :malformed" do
    assert {:error, :malformed} = open("notavalidtoken!!!", @key)
  end