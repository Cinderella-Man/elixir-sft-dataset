  test "replay check takes precedence over expiry", %{server: server} do
    token = SingleUseToken.issue(server, "x", 100)
    assert {:ok, "x"} = SingleUseToken.redeem(server, token)

    # Advance past the token's expiry; a consumed token stays :replayed.
    Clock.advance(500)
    assert {:error, :replayed} = SingleUseToken.redeem(server, token)
  end