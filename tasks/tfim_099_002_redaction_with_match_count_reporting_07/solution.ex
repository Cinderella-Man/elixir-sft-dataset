  test "counts keys_masked across a list of maps", %{r: r} do
    data = [%{user: "a", password: "1"}, %{user: "b", password: "2"}]
    {scrubbed, report} = LogRedactor.redact(r, data)
    [m1, m2] = scrubbed
    assert m1.password == "[REDACTED]"
    assert m2.password == "[REDACTED]"
    assert report.keys_masked == 2
  end