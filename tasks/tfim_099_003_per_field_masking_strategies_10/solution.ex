  test "string values under non-policy keys get pattern-masked" do
    m = FieldMasker.new(%{password: :redact})
    result = FieldMasker.mask(m, %{note: "reach me at john.doe@example.com"})
    assert result.note =~ "j***@example.com"
    refute result.note =~ "john.doe"
  end