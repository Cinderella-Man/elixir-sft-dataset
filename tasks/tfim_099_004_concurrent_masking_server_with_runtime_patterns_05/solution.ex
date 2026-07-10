  test "masks sensitive keys in a keyword list", %{s: s} do
    result = MaskingServer.mask(s, username: "dave", password: "secret!")
    assert result[:username] == "dave"
    assert result[:password] == "[MASKED]"
  end