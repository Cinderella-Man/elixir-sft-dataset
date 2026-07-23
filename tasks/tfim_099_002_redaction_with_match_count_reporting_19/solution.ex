  test "a struct inside a list is returned unchanged", %{r: r} do
    profile = %LogRedactorStructFixture{
      name: "gina",
      password: "pw",
      note: "card 4111111111111234"
    }

    {scrubbed, report} = LogRedactor.redact(r, [profile])
    assert scrubbed == [profile]
    assert report == %{keys_masked: 0, credit_cards: 0, emails: 0, ssns: 0}
  end