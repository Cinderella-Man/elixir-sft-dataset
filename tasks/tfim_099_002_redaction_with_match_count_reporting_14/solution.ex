  test "redact_string masks an SSN", %{r: r} do
    {scrubbed, report} = LogRedactor.redact_string(r, "SSN: 123-45-6789 on file")
    assert scrubbed =~ "***-**-****"
    assert report.ssns == 1
  end