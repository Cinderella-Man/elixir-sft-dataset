  test "expires_at is satisfied strictly before the expiry second" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "expires_at = 100")

    assert :ok = CapabilityToken.authorize(token, @root, %{now: 99})

    assert {:error, {:caveat_failed, "expires_at = 100"}} =
             CapabilityToken.authorize(token, @root, %{now: 100})

    assert {:error, {:caveat_failed, "expires_at = 100"}} =
             CapabilityToken.authorize(token, @root, %{now: 101})
  end