  test "valid base64 with garbage content is malformed" do
    garbage = Base.url_encode64("nowhere near a token structure", padding: false)
    assert {:error, :malformed} = CapabilityToken.authorize(garbage, @root, %{})
    assert {:error, :malformed} = CapabilityToken.inspect_token(garbage)
    assert {:error, :malformed} = CapabilityToken.attenuate(garbage, "action = read")
  end