  test "last4 keeps the final four characters of a long string" do
    m = FieldMasker.new(%{card: :last4})
    result = FieldMasker.mask(m, %{card: "4111111111111234"})
    assert result.card == "************1234"
  end