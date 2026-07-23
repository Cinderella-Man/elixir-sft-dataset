  test "a struct nested under a non-sensitive key is returned unchanged", %{r: r} do
    profile = %LogRedactorStructFixture{name: "frank", password: "pw", note: "a@b.com"}
    {scrubbed, report} = LogRedactor.redact(r, %{user_id: 7, profile: profile})
    assert scrubbed.user_id == 7
    assert scrubbed.profile == profile
    assert report == %{keys_masked: 0, credit_cards: 0, emails: 0, ssns: 0}
  end