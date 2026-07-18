  test "wrong root key yields :invalid_signature" do
    token = CapabilityToken.mint(@root, "u")
    assert {:error, :invalid_signature} = CapabilityToken.authorize(token, "other-key", %{})
  end