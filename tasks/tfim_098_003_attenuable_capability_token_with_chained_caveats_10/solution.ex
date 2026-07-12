  test "expires_at with a non-integer value fails closed" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "expires_at = soon")

    assert {:error, {:caveat_failed, "expires_at = soon"}} =
             CapabilityToken.authorize(token, @root, %{now: 1})
  end