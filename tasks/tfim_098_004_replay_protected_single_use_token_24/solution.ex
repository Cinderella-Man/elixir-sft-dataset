  test "supports integer payload", %{server: server} do
    token = SingleUseToken.issue(server, 12345, 60)
    assert {:ok, 12345} = SingleUseToken.redeem(server, token)
  end