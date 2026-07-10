  test "masks sensitive keys regardless of value type", %{s: s} do
    result = MaskingServer.mask(s, %{password: 12345, token: nil})
    assert result.password == "[MASKED]"
    assert result.token == "[MASKED]"
  end