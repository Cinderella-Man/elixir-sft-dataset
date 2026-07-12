  test "attenuation works without the root key and the result still verifies" do
    base = CapabilityToken.mint(@root, "user:1")
    # No key involved in this step at all.
    narrowed = attenuate!(base, "action = read")
    assert :ok = CapabilityToken.authorize(narrowed, @root, %{action: "read"})
  end