  test "random binary returns :malformed" do
    assert {:error, :malformed} = verify("notavalidtoken!!!", "secret")
  end