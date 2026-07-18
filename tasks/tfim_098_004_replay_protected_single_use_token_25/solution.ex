  test "supports list payload", %{server: server} do
    token = SingleUseToken.issue(server, [1, "two", :three], 60)
    assert {:ok, [1, "two", :three]} = SingleUseToken.redeem(server, token)
  end