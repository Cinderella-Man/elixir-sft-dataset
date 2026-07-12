  test "issued token redeems successfully", %{server: server} do
    token = SingleUseToken.issue(server, %{user_id: 42}, 300)
    assert is_binary(token)
    assert {:ok, %{user_id: 42}} = SingleUseToken.redeem(server, token)
  end