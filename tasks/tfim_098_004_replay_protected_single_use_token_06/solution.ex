  test "consuming one token does not consume an independently issued token",
       %{server: server} do
    t1 = SingleUseToken.issue(server, "a", 300)
    t2 = SingleUseToken.issue(server, "b", 300)

    assert {:ok, "a"} = SingleUseToken.redeem(server, t1)
    # t2 is unaffected by t1's redemption.
    assert {:ok, "b"} = SingleUseToken.redeem(server, t2)
  end