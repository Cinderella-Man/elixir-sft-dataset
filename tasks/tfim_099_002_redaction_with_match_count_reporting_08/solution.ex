  test "masks sensitive keys in a keyword list", %{r: r} do
    {scrubbed, report} =
      LogRedactor.redact(r, username: "dave", password: "secret!", role: :viewer)

    assert scrubbed[:username] == "dave"
    assert scrubbed[:password] == "[REDACTED]"
    assert scrubbed[:role] == :viewer
    assert report.keys_masked == 1
  end