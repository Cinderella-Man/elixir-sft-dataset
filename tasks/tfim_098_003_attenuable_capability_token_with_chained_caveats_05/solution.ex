  test "inspect_token lists caveats in attachment order" do
    token =
      @root
      |> CapabilityToken.mint("user:1")
      |> attenuate!("action = read")
      |> attenuate!("resource_prefix = /docs/")
      |> attenuate!("expires_at = 500")

    assert {:ok, %{identifier: "user:1", caveats: caveats}} =
             CapabilityToken.inspect_token(token)

    assert caveats == ["action = read", "resource_prefix = /docs/", "expires_at = 500"]
  end