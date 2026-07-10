  test "recursively counts keys_masked in nested maps", %{r: r} do
    data = %{user: %{name: "carol", creds: %{password: "hunter2", token: "tok"}}}
    {scrubbed, report} = LogRedactor.redact(r, data)
    assert scrubbed.user.name == "carol"
    assert scrubbed.user.creds.password == "[REDACTED]"
    assert scrubbed.user.creds.token == "[REDACTED]"
    assert report.keys_masked == 2
  end