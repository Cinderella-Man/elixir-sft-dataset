  test "stripping a caveat while keeping the signature yields :invalid_signature" do
    token =
      @root
      |> CapabilityToken.mint("u")
      |> attenuate!("action = read")
      |> attenuate!("expires_at = 100")

    {id, caveats, sig} = raw(token)
    assert length(caveats) == 2

    # Drop the expiry caveat but keep the final signature — the classic
    # macaroon attack. The chain no longer recomputes.
    stripped = pack(id, ["action = read"], sig)
    assert {:error, :invalid_signature} = CapabilityToken.authorize(stripped, @root, %{now: 999})

    # Dropping every caveat is equally hopeless.
    bare = pack(id, [], sig)
    assert {:error, :invalid_signature} = CapabilityToken.authorize(bare, @root, %{now: 999})
  end