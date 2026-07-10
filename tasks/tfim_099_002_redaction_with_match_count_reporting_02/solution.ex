  test "masks sensitive keys and reports keys_masked", %{r: r} do
    {scrubbed, report} = LogRedactor.redact(r, %{username: "alice", password: "s3cr3t"})
    assert scrubbed.username == "alice"
    assert scrubbed.password == "[REDACTED]"
    assert report.keys_masked == 1
  end