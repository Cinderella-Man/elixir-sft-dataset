  test "all caveats must hold simultaneously" do
    token =
      @root
      |> CapabilityToken.mint("u")
      |> attenuate!("action = read")
      |> attenuate!("resource_prefix = /docs/")
      |> attenuate!("expires_at = 500")

    ctx = %{action: "read", resource: "/docs/x", now: 499}
    assert :ok = CapabilityToken.authorize(token, @root, ctx)

    assert {:error, {:caveat_failed, "expires_at = 500"}} =
             CapabilityToken.authorize(token, @root, %{ctx | now: 500})

    assert {:error, {:caveat_failed, "resource_prefix = /docs/"}} =
             CapabilityToken.authorize(token, @root, %{ctx | resource: "/etc/passwd"})
  end