  test "a token can be redeemed only once; the second redemption is :replayed",
       %{server: server} do
    token = SingleUseToken.issue(server, "once", 300)
    assert {:ok, "once"} = SingleUseToken.redeem(server, token)
    assert {:error, :replayed} = SingleUseToken.redeem(server, token)
  end