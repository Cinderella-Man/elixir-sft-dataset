  test "redact_string counts multiple matches of the same type", %{r: r} do
    {scrubbed, report} = LogRedactor.redact_string(r, "123-45-6789 and 987-65-4321")
    assert scrubbed == "***-**-**** and ***-**-****"
    assert report.ssns == 2
  end