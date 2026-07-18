  test "different keys can use different strategies" do
    m = FieldMasker.new(%{password: :redact, card: :last4})
    result = FieldMasker.mask(m, %{password: "x", card: "5500005555555559"})
    assert result.password == "[MASKED]"
    assert result.card == "************5559"
  end