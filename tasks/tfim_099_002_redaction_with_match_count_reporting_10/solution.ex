  test "sensitive-key values are not additionally pattern-scanned", %{r: r} do
    # password's value looks like an SSN, but is redacted wholesale, not counted as an SSN match
    {scrubbed, report} = LogRedactor.redact(r, %{password: "123-45-6789"})
    assert scrubbed.password == "[REDACTED]"
    assert report.keys_masked == 1
    assert report.ssns == 0
  end