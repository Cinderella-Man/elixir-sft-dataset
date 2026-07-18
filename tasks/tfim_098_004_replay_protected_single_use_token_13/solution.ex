  test "redeeming a token does not consume another token with the identical payload",
       %{server: server} do
    t1 = SingleUseToken.issue(server, %{user_id: 7}, 300)
    t2 = SingleUseToken.issue(server, %{user_id: 7}, 300)

    assert {:ok, %{user_id: 7}} = SingleUseToken.redeem(server, t1)
    # Distinct nonces: t1's redemption leaves t2 fully redeemable.
    assert {:ok, %{user_id: 7}} = SingleUseToken.redeem(server, t2)

    # Each token is now individually consumed.
    assert {:error, :replayed} = SingleUseToken.redeem(server, t1)
    assert {:error, :replayed} = SingleUseToken.redeem(server, t2)
  end