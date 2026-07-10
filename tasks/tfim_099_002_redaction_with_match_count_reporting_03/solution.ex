  test "masks sensitive keys regardless of value type", %{r: r} do
    {scrubbed, report} = LogRedactor.redact(r, %{password: 12345, token: nil, secret: [1, 2, 3]})
    assert scrubbed.password == "[REDACTED]"
    assert scrubbed.token == "[REDACTED]"
    assert scrubbed.secret == "[REDACTED]"
    assert report.keys_masked == 3
  end