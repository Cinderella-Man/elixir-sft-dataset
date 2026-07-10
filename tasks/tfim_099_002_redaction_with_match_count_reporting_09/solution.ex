  test "pattern-masks string values under non-sensitive keys and counts them", %{r: r} do
    data = %{message: "ssn 123-45-6789 email a@b.com card 4111-1111-1111-1234"}
    {scrubbed, report} = LogRedactor.redact(r, data)
    refute scrubbed.message =~ "123-45-6789"
    refute scrubbed.message =~ "a@b.com"
    refute scrubbed.message =~ "4111-1111-1111"
    assert scrubbed.message =~ "1234"
    assert report.keys_masked == 0
    assert report.credit_cards == 1
    assert report.emails == 1
    assert report.ssns == 1
  end