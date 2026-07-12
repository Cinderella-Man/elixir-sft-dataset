  test "token expires exactly at ttl boundary", %{server: server} do
    token = SingleUseToken.issue(server, "data", 50)
    Clock.advance(50)
    assert {:error, :expired} = SingleUseToken.redeem(server, token)
  end