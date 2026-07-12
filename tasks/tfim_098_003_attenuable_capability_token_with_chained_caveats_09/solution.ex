  test "expires_at fails closed when the context has no :now" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "expires_at = 100")

    assert {:error, {:caveat_failed, "expires_at = 100"}} =
             CapabilityToken.authorize(token, @root, %{action: "read"})
  end