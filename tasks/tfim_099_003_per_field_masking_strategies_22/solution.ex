  test "a struct value under a non-policy key is returned unchanged" do
    m = FieldMasker.new(%{password: :redact})
    uri = URI.parse("mailto:john.doe@example.com")
    result = FieldMasker.mask(m, %{contact: uri})
    assert result.contact == uri
  end