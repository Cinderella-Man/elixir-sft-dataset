  test "truncated token returns :malformed", %{server: server} do
    token = SingleUseToken.issue(server, "hello", 60)
    truncated = binary_part(token, 0, div(byte_size(token), 2))
    assert {:error, :malformed} = SingleUseToken.redeem(server, truncated)
  end