  test "last4 keeps the raw final four digits of an SSN-shaped value" do
    # Scrubbing first would yield "***-**-****", whose last four characters
    # are stars; the strategy must operate on the untouched value.
    m = FieldMasker.new(%{ssn: :last4})
    result = FieldMasker.mask(m, %{ssn: "123-45-6789"})
    assert result.ssn == "*******6789"
  end