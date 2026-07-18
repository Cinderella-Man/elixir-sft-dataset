  test "valid base64 but garbage content returns :malformed", %{server: server} do
    garbage = Base.url_encode64("this is not a valid token structure", padding: false)
    assert {:error, :malformed} = SingleUseToken.redeem(server, garbage)
  end