  test "a top-level struct is returned unchanged with an all-zero report", %{r: r} do
    original = %LogRedactorStructFixture{
      name: "erin",
      password: "hunter2",
      note: "ssn 123-45-6789"
    }

    assert LogRedactor.redact(r, original) ==
             {original, %{keys_masked: 0, credit_cards: 0, emails: 0, ssns: 0}}
  end