  test "hash digests the raw value, not a pattern-scrubbed rewrite of it" do
    # The strategy sees the original "123-45-6789"; had the SSN pattern been
    # scrubbed to "***-**-****" first, the digest would differ.
    m = FieldMasker.new(%{ssn: :hash})
    result = FieldMasker.mask(m, %{ssn: "123-45-6789"})
    expected = "sha256:" <> Base.encode16(:crypto.hash(:sha256, "123-45-6789"), case: :lower)
    assert result.ssn == expected
  end