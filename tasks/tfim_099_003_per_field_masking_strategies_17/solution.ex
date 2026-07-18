  test "policies given as a keyword list work the same" do
    m = FieldMasker.new(password: :redact, card: :last4)
    result = FieldMasker.mask(m, %{password: "x", card: "4111111111111234"})
    assert result.password == "[MASKED]"
    assert result.card == "************1234"
  end