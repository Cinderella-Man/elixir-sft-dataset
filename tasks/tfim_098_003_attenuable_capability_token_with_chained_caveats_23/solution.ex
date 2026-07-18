  test "reordering caveats yields :invalid_signature" do
    token =
      @root
      |> CapabilityToken.mint("u")
      |> attenuate!("action = read")
      |> attenuate!("resource_prefix = /docs/")

    {id, [c1, c2], sig} = raw(token)
    swapped = pack(id, [c2, c1], sig)

    assert {:error, :invalid_signature} =
             CapabilityToken.authorize(swapped, @root, %{action: "read", resource: "/docs/x"})
  end