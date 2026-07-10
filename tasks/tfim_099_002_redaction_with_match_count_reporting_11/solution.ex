  test "empty map yields an all-zero report", %{r: r} do
    assert LogRedactor.redact(r, %{}) ==
             {%{}, %{keys_masked: 0, credit_cards: 0, emails: 0, ssns: 0}}
  end