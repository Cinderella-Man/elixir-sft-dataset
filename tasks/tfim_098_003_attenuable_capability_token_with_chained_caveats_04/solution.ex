  test "inspect_token exposes identifier and empty caveat list" do
    token = CapabilityToken.mint(@root, "svc:billing")
    assert {:ok, %{identifier: "svc:billing", caveats: []}} = CapabilityToken.inspect_token(token)
  end