  test "empty string is malformed" do
    assert {:error, :malformed} = CapabilityToken.authorize("", @root, %{})
    assert {:error, :malformed} = CapabilityToken.inspect_token("")
    assert {:error, :malformed} = CapabilityToken.attenuate("", "action = read")
  end