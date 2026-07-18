  test "empty string returns :malformed", %{server: server} do
    assert {:error, :malformed} = SingleUseToken.redeem(server, "")
  end