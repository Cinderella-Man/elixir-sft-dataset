  test "payload is preserved exactly through round-trip", %{server: server} do
    payload = %{role: "admin", sub: "user:99", meta: [1, 2, 3]}
    token = SingleUseToken.issue(server, payload, 60)
    assert {:ok, ^payload} = SingleUseToken.redeem(server, token)
  end