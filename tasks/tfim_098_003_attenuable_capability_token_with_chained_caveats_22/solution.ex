  test "editing a caveat's text yields :invalid_signature" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "action = read")
    {id, _caveats, sig} = raw(token)

    widened = pack(id, ["action = admn"], sig)

    assert {:error, :invalid_signature} =
             CapabilityToken.authorize(widened, @root, %{action: "admn"})
  end