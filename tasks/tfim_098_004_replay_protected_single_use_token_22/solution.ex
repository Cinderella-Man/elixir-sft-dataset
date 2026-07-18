  test "non-binary token input returns :malformed", %{server: server} do
    assert {:error, :malformed} = SingleUseToken.redeem(server, 12345)
  end