  test "a wrong version byte is malformed" do
    token = CapabilityToken.mint(@root, "u")
    {:ok, <<1, rest::binary>>} = Base.url_decode64(token, padding: false)
    bad = Base.url_encode64(<<2, rest::binary>>, padding: false)

    assert {:error, :malformed} = CapabilityToken.authorize(bad, @root, %{})
    assert {:error, :malformed} = CapabilityToken.inspect_token(bad)
  end