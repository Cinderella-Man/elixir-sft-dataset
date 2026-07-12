  test "attenuate does not mutate the original token" do
    base = CapabilityToken.mint(@root, "user:1")
    narrowed = attenuate!(base, "action = read")

    refute base == narrowed
    assert {:ok, %{caveats: []}} = CapabilityToken.inspect_token(base)
    assert {:ok, %{caveats: ["action = read"]}} = CapabilityToken.inspect_token(narrowed)
    assert :ok = CapabilityToken.authorize(base, @root, %{action: "write"})
  end