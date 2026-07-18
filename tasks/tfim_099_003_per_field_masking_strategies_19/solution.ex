  test "hash strategy hashes the inspect representation of a non-string value" do
    m = FieldMasker.new(%{password: :hash})
    result = FieldMasker.mask(m, %{password: :secret})
    expected = "sha256:" <> Base.encode16(:crypto.hash(:sha256, inspect(:secret)), case: :lower)
    assert result.password == expected
  end