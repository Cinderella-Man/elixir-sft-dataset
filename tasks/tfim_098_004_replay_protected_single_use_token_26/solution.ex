  test "supports deeply nested map payload", %{server: server} do
    payload = %{a: %{b: %{c: "deep"}}}
    token = SingleUseToken.issue(server, payload, 60)
    assert {:ok, ^payload} = SingleUseToken.redeem(server, token)
  end