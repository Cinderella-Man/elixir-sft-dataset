  test "redact_string masks an email keeping the first char", %{r: r} do
    {scrubbed, report} = LogRedactor.redact_string(r, "Contact john.doe@example.com please")
    assert scrubbed =~ "j***@example.com"
    refute scrubbed =~ "john.doe"
    assert report.emails == 1
  end