  test "swapping the identifier yields :invalid_signature" do
    token = CapabilityToken.mint(@root, "user:1")
    {_id, caveats, sig} = raw(token)
    forged = pack("user:2", caveats, sig)

    assert {:error, :invalid_signature} = CapabilityToken.authorize(forged, @root, %{})
  end