  test "redact strategy blanks non-string values too" do
    m = FieldMasker.new(%{token: :redact})
    result = FieldMasker.mask(m, %{token: 12345})
    assert result.token == "[MASKED]"
  end