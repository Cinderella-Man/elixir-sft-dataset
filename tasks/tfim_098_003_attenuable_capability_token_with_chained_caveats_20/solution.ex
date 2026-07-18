  test "flipping a signature byte yields :invalid_signature" do
    token = CapabilityToken.mint(@root, "u")
    {id, caveats, <<head::binary-size(31), last::8>>} = raw(token)
    forged = pack(id, caveats, <<head::binary, Bitwise.bxor(last, 1)::8>>)

    assert {:error, :invalid_signature} = CapabilityToken.authorize(forged, @root, %{})
  end