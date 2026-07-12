  test "a freshly minted token authorizes with any context" do
    token = CapabilityToken.mint(@root, "user:42")
    assert is_binary(token)
    assert :ok = CapabilityToken.authorize(token, @root, %{})
    assert :ok = CapabilityToken.authorize(token, @root, %{now: 1_000, action: "read"})
  end