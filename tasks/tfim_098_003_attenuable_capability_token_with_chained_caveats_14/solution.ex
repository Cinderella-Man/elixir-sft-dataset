  test "a caveat without the separator fails closed" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "always-allow")

    assert {:error, {:caveat_failed, "always-allow"}} =
             CapabilityToken.authorize(token, @root, %{now: 1})
  end