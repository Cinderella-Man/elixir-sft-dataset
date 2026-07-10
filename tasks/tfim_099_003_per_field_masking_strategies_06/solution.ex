  test "last4 leaves an empty string empty" do
    m = FieldMasker.new(%{code: :last4})
    result = FieldMasker.mask(m, %{code: ""})
    assert result.code == ""
  end