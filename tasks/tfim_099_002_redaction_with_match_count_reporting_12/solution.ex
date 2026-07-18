  test "redact_string masks a dashed credit card and reports one card", %{r: r} do
    {scrubbed, report} = LogRedactor.redact_string(r, "4111-1111-1111-1234")
    assert scrubbed == "****-****-****-1234"
    assert report.credit_cards == 1
    assert report.keys_masked == 0
  end