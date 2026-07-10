  test "masks sensitive keys whose value is a non-string (integer, nil, list)", %{m: m} do
    result = LogMasker.mask(m, %{password: 12345, token: nil, secret: [1, 2, 3]})
    assert result.password == "[MASKED]"
    assert result.token == "[MASKED]"
    assert result.secret == "[MASKED]"
  end