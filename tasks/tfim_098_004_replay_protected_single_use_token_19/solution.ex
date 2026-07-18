  test "random binary returns :malformed", %{server: server} do
    assert {:error, :malformed} = SingleUseToken.redeem(server, "notavalidtoken!!!")
  end