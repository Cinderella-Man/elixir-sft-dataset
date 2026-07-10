  test "non-policy non-string values are untouched" do
    m = FieldMasker.new(%{password: :redact})
    result = FieldMasker.mask(m, %{count: 7, active: true})
    assert result.count == 7
    assert result.active == true
  end