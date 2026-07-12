  test "expired, never-consumed token returns :expired", %{server: server} do
    token = SingleUseToken.issue(server, "data", 100)
    Clock.advance(101)
    assert {:error, :expired} = SingleUseToken.redeem(server, token)
  end