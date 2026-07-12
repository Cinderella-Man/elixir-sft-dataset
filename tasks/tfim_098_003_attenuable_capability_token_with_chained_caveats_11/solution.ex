  test "action caveat requires an exact match" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "action = read")

    assert :ok = CapabilityToken.authorize(token, @root, %{action: "read"})

    assert {:error, {:caveat_failed, "action = read"}} =
             CapabilityToken.authorize(token, @root, %{action: "write"})

    assert {:error, {:caveat_failed, "action = read"}} =
             CapabilityToken.authorize(token, @root, %{})
  end