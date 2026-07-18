  test "non-base64 garbage is malformed" do
    assert {:error, :malformed} = CapabilityToken.authorize("not a token!!!", @root, %{})
    assert {:error, :malformed} = CapabilityToken.inspect_token("not a token!!!")
  end