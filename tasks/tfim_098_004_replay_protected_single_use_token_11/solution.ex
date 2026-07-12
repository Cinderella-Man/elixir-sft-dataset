  test "an expired token is not consumed, so it never becomes :replayed",
       %{server: server} do
    token = SingleUseToken.issue(server, "data", 100)
    Clock.advance(101)
    assert {:error, :expired} = SingleUseToken.redeem(server, token)
    # Still :expired, not :replayed — the failed redemption consumed nothing.
    assert {:error, :expired} = SingleUseToken.redeem(server, token)
  end