  test "case-insensitive matching for string keys", %{r: r} do
    {scrubbed, report} = LogRedactor.redact(r, %{"Password" => "x", "TOKEN" => "y"})
    assert scrubbed["Password"] == "[REDACTED]"
    assert scrubbed["TOKEN"] == "[REDACTED]"
    assert report.keys_masked == 2
  end