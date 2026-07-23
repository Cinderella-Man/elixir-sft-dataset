  test "hash digests a raw e-mail value rather than its pattern-masked form" do
    m = FieldMasker.new(%{contact: :hash})
    result = FieldMasker.mask(m, %{contact: "john.doe@example.com"})

    expected =
      "sha256:" <> Base.encode16(:crypto.hash(:sha256, "john.doe@example.com"), case: :lower)

    assert result.contact == expected
  end