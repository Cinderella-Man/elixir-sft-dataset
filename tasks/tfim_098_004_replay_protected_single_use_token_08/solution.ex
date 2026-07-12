  test "token is valid just before expiry", %{server: server} do
    token = SingleUseToken.issue(server, "data", 100)
    Clock.advance(99)
    assert {:ok, "data"} = SingleUseToken.redeem(server, token)
  end