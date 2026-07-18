  test "redact_string on a clean string returns it unchanged with a zero report", %{r: r} do
    {scrubbed, report} = LogRedactor.redact_string(r, "nothing sensitive here")
    assert scrubbed == "nothing sensitive here"
    assert report == %{keys_masked: 0, credit_cards: 0, emails: 0, ssns: 0}
  end