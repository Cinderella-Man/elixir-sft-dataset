  test "supports atom payload", %{server: server} do
    token = SingleUseToken.issue(server, :hello, 60)
    assert {:ok, :hello} = SingleUseToken.redeem(server, token)
  end