  test "a strategy-transformed value is not additionally pattern-scanned" do
    # value looks like an SSN but :redact wins wholesale
    m = FieldMasker.new(%{ssn: :redact})
    result = FieldMasker.mask(m, %{ssn: "123-45-6789"})
    assert result.ssn == "[MASKED]"
  end