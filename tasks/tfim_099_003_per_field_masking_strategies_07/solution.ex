  test "last4 on a non-string value falls back to [MASKED]" do
    m = FieldMasker.new(%{card: :last4})
    result = FieldMasker.mask(m, %{card: 42})
    assert result.card == "[MASKED]"
  end